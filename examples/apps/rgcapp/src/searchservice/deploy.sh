#!/usr/bin/env bash
# vim:syn=sh:ts=4:sw=4:et:ai

set -ex

if [ -z $AWS_ACCOUNT_ID ]; then
    echo "AWS_ACCOUNT_ID environment variable is not set."
    exit 1
fi

if [ -z $AWS_DEFAULT_REGION ]; then
    echo "AWS_DEFAULT_REGION environment variable is not set."
    exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SEARCH_SERVICE_IMAGE=${SEARCH_SERVICE_IMAGE:-"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/rgc/searchservice"}
GO_PROXY=${GO_PROXY:-"https://proxy.golang.org"}

# build
docker build --build-arg GO_PROXY=$GO_PROXY -t $SEARCH_SERVICE_IMAGE ${DIR}

# push
$(aws ecr get-login --no-include-email)
docker push $SEARCH_SERVICE_IMAGE
