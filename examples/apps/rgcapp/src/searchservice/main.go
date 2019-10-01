package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/aws/aws-xray-sdk-go/xray"
)

const defaultPort = "8080"
const defaultTag = "Tesla"
const defaultStage = "default"

func getServerPort() string {
	port := os.Getenv("SERVER_PORT")
	if port != "" {
		return port
	}

	return defaultPort
}

func getTag() string {
	tag := os.Getenv("TAG")
	if tag != "" {
		return tag
	}

	return defaultTag
}

func getStage() string {
	stage := os.Getenv("STAGE")
	if stage != "" {
		return stage
	}

	return defaultStage
}

type tagHandler struct{}

func (h *tagHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	log.Println("tag requested, responding with", getTag())
	fmt.Fprint(writer, getTag())
}

type pingHandler struct{}

func (h *pingHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	log.Println("ping requested, reponding with HTTP 200")
	writer.WriteHeader(http.StatusOK)
}

func main() {
	log.Println("starting server, listening on port " + getServerPort())
	xraySegmentNamer := xray.NewFixedSegmentNamer(fmt.Sprintf("%s-searchservice-%s", getStage(), getTag()))
	http.Handle("/", xray.Handler(xraySegmentNamer, &tagHandler{}))
	http.Handle("/ping", xray.Handler(xraySegmentNamer, &pingHandler{}))
	http.ListenAndServe(":"+getServerPort(), nil)
}
