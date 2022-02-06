#!/bin/bash

CURRENT_DIR=$(dirname $(realpath "$0"))
ROOT_DIR=$(dirname "$CURRENT_DIR")
DOCKER_COMMAND=${DOCKER_COMMAND:-"docker build"}

if [[ -z $1 ]]; then
  echo "usage: $(basename $0) <version> <docker image>"
  exit 1
fi

if [[ -z $2 ]]; then
  echo "usage: $(basename $0) <version> <docker image>"
  exit 1
fi

VERSION=$1
IMAGE_NAME=$2

set -e
echo "Building docker image ${IMAGE_NAME}:${VERSION}"
$DOCKER_COMMAND -f ${ROOT_DIR}/btfserver.Dockerfile -t "${IMAGE_NAME}:${VERSION}" ${ROOT_DIR}
echo "Building docker image ${IMAGE_NAME}:${VERSION} - done"
docker push "${IMAGE_NAME}:${VERSION}"

echo "Done"
