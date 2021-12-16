#!/bin/bash

CURRENT_DIR=$(dirname $(realpath "$0"))
ROOT_DIR=$(dirname "$CURRENT_DIR")
IMAGE_NAME=${IMAGE_NAME:-"us.gcr.io/seekret/btfhub"}
DOCKER_COMMAND=${DOCKER_COMMAND:-"docker build"}

if [[ -z $1 ]]; then
  echo "usage: $(basename $0) <version>"
  exit 1
fi

VERSION=$1

set -e
echo "Building docker image ${IMAGE_NAME}:${VERSION}"
$DOCKER_COMMAND -f ${ROOT_DIR}/Dockerfile -t "${IMAGE_NAME}:${VERSION}" ${ROOT_DIR}
echo "Building docker image ${IMAGE_NAME}:${VERSION} - done"
docker push "${IMAGE_NAME}:${VERSION}"

echo "Done"
