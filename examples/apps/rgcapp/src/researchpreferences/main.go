package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"math"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"

	"github.com/aws/aws-xray-sdk-go/xray"
	"github.com/pkg/errors"
)

const defaultPort = "8080"
const defaultStage = "default"
const maxTags = 1000

var tags [maxTags]string
var tagsIdx int
var tagsMutext = &sync.Mutex{}

func getServerPort() string {
	port := os.Getenv("SERVER_PORT")
	if port != "" {
		return port
	}

	return defaultPort
}

func getStage() string {
	stage := os.Getenv("STAGE")
	if stage != "" {
		return stage
	}

	return defaultStage
}

func getSearchServiceEndpoint() (string, error) {
	searchServiceEndpoint := os.Getenv("SEARCH_SERVICE_ENDPOINT")
	if searchServiceEndpoint == "" {
		return "", errors.New("SEARCH_SERVICE_ENDPOINT is not set")
	}
	return searchServiceEndpoint, nil
}

type tagHandler struct{}

func (h *tagHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	tag, err := getTagFromSearchService(request)
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		writer.Write([]byte("500 - Unexpected Error"))
		return
	}

	tagsMutext.Lock()
	defer tagsMutext.Unlock()

	addTag(tag)
	statsJson, err := json.Marshal(getRatios())
	if err != nil {
		fmt.Fprintf(writer, `{"tag":"%s", "error":"%s"}`, tag, err)
		return
	}
	fmt.Fprintf(writer, `{"tag":"%s", "stats": %s}`, tag, statsJson)
}

func addTag(tag string) {
	tags[tagsIdx] = tag

	tagsIdx += 1
	if tagsIdx >= maxTags {
		tagsIdx = 0
	}
}

func getRatios() map[string]float64 {
	counts := make(map[string]int)
	var total = 0

	for _, c := range tags {
		if c != "" {
			counts[c] += 1
			total += 1
		}
	}

	ratios := make(map[string]float64)
	for k, v := range counts {
		ratio := float64(v) / float64(total)
		ratios[k] = math.Round(ratio*100) / 100
	}

	return ratios
}

type clearTagStatsHandler struct{}

func (h *clearTagStatsHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	tagsMutext.Lock()
	defer tagsMutext.Unlock()

	tagsIdx = 0
	for i := range tags {
		tags[i] = ""
	}

	fmt.Fprint(writer, "cleared")
}

func getTagFromSearchService(request *http.Request) (string, error) {
	searchServiceEndpoint, err := getSearchServiceEndpoint()
	if err != nil {
		return "-n/a-", err
	}

	client := xray.Client(&http.Client{})
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("http://%s", searchServiceEndpoint), nil)
	if err != nil {
		return "-n/a-", err
	}

	resp, err := client.Do(req.WithContext(request.Context()))
	if err != nil {
		return "-n/a-", err
	}

	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "-n/a-", err
	}

	tag := strings.TrimSpace(string(body))
	if len(tag) < 1 {
		return "-n/a-", errors.New("Empty response from searchService")
	}

	return tag, nil
}

func getTCPEchoEndpoint() (string, error) {
	tcpEchoEndpoint := os.Getenv("TCP_ECHO_ENDPOINT")
	if tcpEchoEndpoint == "" {
		return "", errors.New("TCP_ECHO_ENDPOINT is not set")
	}
	return tcpEchoEndpoint, nil
}

type tcpEchoHandler struct{}

func (h *tcpEchoHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	endpoint, err := getTCPEchoEndpoint()
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(writer, "tcpecho endpoint is not set")
		return
	}

	log.Printf("Dialing tcp endpoint %s", endpoint)
	conn, err := net.Dial("tcp", endpoint)
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(writer, "Dial failed, err:%s", err.Error())
		return
	}
	defer conn.Close()

	strEcho := "Hello from gateway"
	log.Printf("Writing '%s'", strEcho)
	_, err = fmt.Fprintf(conn, strEcho)
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(writer, "Write to server failed, err:%s", err.Error())
		return
	}

	reply, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		writer.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(writer, "Read from server failed, err:%s", err.Error())
		return
	}

	fmt.Fprintf(writer, "Response from tcpecho server: %s", reply)
}

type pingHandler struct{}

func (h *pingHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	log.Println("ping requested, reponding with HTTP 200")
	writer.WriteHeader(http.StatusOK)
}

func main() {
	log.Println("Starting server, listening on port " + getServerPort())

	searchServiceEndpoint, err := getSearchServiceEndpoint()
	if err != nil {
		log.Fatalln(err)
	}
	tcpEchoEndpoint, err := getTCPEchoEndpoint()
	if err != nil {
		log.Println(err)
	}

	log.Println("Using search-service at " + searchServiceEndpoint)
	log.Println("Using tcp-echo at " + tcpEchoEndpoint)

	xraySegmentNamer := xray.NewFixedSegmentNamer(fmt.Sprintf("%s-researchpreferences", getStage()))

	http.Handle("/tag", xray.Handler(xraySegmentNamer, &tagHandler{}))
	http.Handle("/tag/clear", xray.Handler(xraySegmentNamer, &clearTagStatsHandler{}))
	http.Handle("/tcpecho", xray.Handler(xraySegmentNamer, &tcpEchoHandler{}))
	http.Handle("/ping", xray.Handler(xraySegmentNamer, &pingHandler{}))
	log.Fatal(http.ListenAndServe(":"+getServerPort(), nil))
}
