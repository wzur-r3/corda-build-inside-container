#!/bin/bash

set -eu -o pipefail

$(dirname "$0")/with-docker-container.sh \
  --shell bash \
  --name corda-docs-builder \
  --dockerfile=$(dirname "$0")/Dockerfile-corda-builder \
  --build-arg=builder_user=$(id -un) \
  --build-arg=builder_uid=$(id -u) \
  --gid=$(getent group docker | cut -d: -f3) \
  --env=GRADLE_USER_HOME=`pwd`/.gradle_user_home \
  --unset-env=JAVA_HOME \
  --volume=/var/run/docker.sock:/var/run/docker.sock \
  ${SSH_AUTH_SOCK+"--volume=${SSH_AUTH_SOCK}:${SSH_AUTH_SOCK}"} \
  -- \
  ${1+"$@"}
