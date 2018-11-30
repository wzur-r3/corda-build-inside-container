#!/bin/bash
#/
#/ Execute a command (or a script) inside a Docker container
#/ It uses either a Docker image or build one from provided Dockerfile,
#/ starts a Docker container from that image and executes command given as an argument.
#/
#/ Options:
#/   -v, --verbose - more verbose output
#/   -h, --help - this information
#/   -f, --dockerfile DOCKERFILE - the Dockerfile to build the Docker image from (default is `Dockerfile`)
#/   -i, --image DOCKER_IMAGE - the Docker image to pull & start the container from, this option cannot be used with -f
#/   -e, --env VAR_NAME - the name of the environment variable to pass to the executed command
#/   -s, --shell SHELL - the command line shell to execetute commands with (default is `sh`)
#/   -u, --run-as USER_NAME - the name of an user the command should be executed as (default is the user who starts this scripts)
#/   --uid USER_ID - the system ID the user the command should be executed as (default is the ID of the user who starts this scripts)
#/   --gid GROUP_ID - the system ID of the group the command should be executed as (default is the ID of the default group of the user who starts this scripts)
#/   --build-arg - passed to a Docker build command, used if a Dockerfile contains ARG
#/   --volume - passed to a Docker run command, used to share additional folders with the Docker container
#/
#/ Example:
#/   with-docker-container.sh -- echo Hello there
#/   with-docker-container.sh -i ubuntu -- id

set -eu

#
# Display usage of the script, which is a specially marked comment
#
usage() {
  grep '^#/' <"$0" | cut -c 4-
}

#
# Check if the debug mode has been enabled, ie ${DEBUG} is set to true
#
is_debug() {
  "${DEBUG:-false}"
}

#
# Display some debug message if debug mode has been enabled
#
# Example: debug Some debug message here
#
debug() {
  if is_debug
  then
    echo "$@" >&2
  fi
}

#
# Exits the process with a status indicating error
#
error() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $@" >> /dev/stderr
    exit 1
}

#
# Join strings with a separator
#
# Example: join , a b c d
#
join () {
    local IFS="$1"; shift
    echo "$*"
}

declare -A SCRIPT_OPTIONS=(
 [help]=h
 [verbose]=v
 [dockerfile:]=f:
 [image:]=i:
 [env:]=e:
 [shell:]=s:
 [run-as:]=u:
 [build-arg:]=
 [volume:]=
 [uid:]=
 [gid:]=
)

OPTS=$(getopt -o $(join "" "${SCRIPT_OPTIONS[@]}") --long $(join , "${!SCRIPT_OPTIONS[@]}") -n "${0}" -- "$@")

if [ $? != 0 ] ; then error "Failed parsing options." ; exit 1 ; fi

eval set -- "$OPTS"

DOCKERFILE=Dockerfile
declare -a EXTRA_ENV
DOCKER_SHELL=sh
declare -a DOCKER_BUILD_ARGS
declare -a DOCKER_VOLUMES

WORKDIR=$(pwd)
BUILDER_USER=$(id -un)
BUILDER_UID=$(id -u)
BUILDER_GID=$(id -g)

while true; do
  case "$1" in
    -v) DEBUG=true; shift ;;
    -f | --dockerfile) DOCKERFILE="$2"; shift; shift ;;
    -i | --image) DOCKERIMAGE="$2"; shift; shift ;;
    -e | --env) EXTRA_ENV+=("$2"); shift; shift ;;
    -s | --shell) DOCKER_SHELL="$2"; shift; shift ;;
    -u | --run-as) BUILDER_USER="$2"; shift; shift ;;
    --build-arg) DOCKER_BUILD_ARGS+=("--build-arg=$2"); shift; shift ;;
    --volume) DOCKER_VOLUMES+=("--volume=$2"); shift; shift ;;
    --uid) BUILDER_UID="$2"; shift; shift ;;
    --gid) BUILDER_GID="$2"; shift; shift ;;
    -h | --help )    usage; exit 75 ;;
    -- ) shift; break ;;
    * ) echo "Don't know what to do with $1"; usage; exit 75 ;;
  esac
done

# At this point there shouldn't be any arguments

# TODO - parameters checking & verification

if [ $# -eq 0 ]
then
  set -- "${DOCKER_SHELL}"
fi

#ME=$(cd $(dirname "$0") && pwd)
#Dockerfile="${ME}/Dockerfile"
DOCKERCONTEXT=$(cd $(dirname "${DOCKERFILE}") && pwd)
DOCKERIMAGE=$(basename $(cd "${WORKDIR}" && pwd))

debug "$(declare -p DOCKERFILE)"
debug "$(declare -p DOCKERIMAGE)"
debug "$(declare -p EXTRA_ENV)"
debug "$(declare -p DOCKER_SHELL)"
debug "$(declare -p BUILDER_USER)"
debug "$(declare -p DOCKER_BUILD_ARGS)"
debug "$(declare -p DOCKER_VOLUMES)"
debug "$(declare -p BUILDER_USER)"
debug "$(declare -p BUILDER_UID)"
debug "$(declare -p BUILDER_GID)"

debug "$(declare -p WORKDIR)"
debug "$(declare -p DOCKERCONTEXT)"

debug "Command: $@"

buildNo=$[$(docker images -qa --filter "label=${DOCKERIMAGE}" | uniq | xargs docker inspect --format '{{ join .RepoTags " " }}' 2>/dev/null | grep latest | cut -f1 -d' ' | cut -f2 -d:) + 1]

debug "$(declare -p buildNo)"

# build an image from provided Dockerfile
docker build \
  -t ${DOCKERIMAGE}:${buildNo} \
  -t ${DOCKERIMAGE}:latest \
  "${DOCKER_BUILD_ARGS[@]}" \
  --force-rm \
  --label="${DOCKERIMAGE}=${buildNo}" \
  -f "${DOCKERFILE}" \
  "${DOCKERCONTEXT}"

# prepare Shell environments to be passed to the container
tempFile=$(mktemp)
# dump all exported Shell variables
env >"${tempFile}"
# add variable defined in the image
docker run -t --rm --user "${BUILDER_UID}:${BUILDER_GID}" "${DOCKERIMAGE}:${buildNo}" env >>"${tempFile}"
# add variables defined in the command line
for pair in "${EXTRA_ENV[@]}"
do
  echo "${pair}" >>"${tempFile}"
done

# start a container from created image
containerId=$(docker run -t -d \
  --user `id -u`:`id -g` \
  "${DOCKER_VOLUMES[@]}" \
  -v "${WORKDIR}:${WORKDIR}" \
  -w "${WORKDIR}" \
  --env-file="${tempFile}" \
  --entrypoint /bin/cat "${DOCKERIMAGE}:${buildNo}")

# create a function to properly clean up after exit
trap 'docker rm -f ${containerId} --volumes 2>/dev/null || true; rm -f "${tempFile}"' EXIT

defaultGroupName="g${containerId:0:7}"

debug "$(declare -p containerId)"
debug "$(declare -p tempFile)"

# make sure requested group exists, if not - create it with some random name
#docker exec -it -u 0:0 "${containerId}" sh -c "getent group '${BUILDER_GID}' &>/dev/null || groupadd --gid '${BUILDER_GID}' '${defaultGroupName}' 2>/dev/null"
docker exec -i -u 0:0 "${containerId}" sh -c "getent group '${BUILDER_GID}' >/dev/null 2>&1 || groupadd --gid '${BUILDER_GID}' '${defaultGroupName}' 2>/dev/null"
# make sure requested user exists, if not - create it
docker exec -i -u 0:0 "${containerId}" sh -c "getent passwd '${BUILDER_USER}' >/dev/null 2>&1 || useradd --uid '${BUILDER_UID}' -m '${BUILDER_USER}' 2>/dev/null"
# make sure user is a member of requested group
docker exec -i -u 0:0 "${containerId}" sh -c "usermod -a -G '${BUILDER_GID}' '${BUILDER_USER}' || bash"

echo ${1+"$@"} | docker exec -u "${BUILDER_USER}" -i ${containerId} sh -c 'cat - >/tmp/command.sh && chmod a+x /tmp/command.sh'

docker exec -u "${BUILDER_USER}:${BUILDER_GID}" -it ${containerId} "${DOCKER_SHELL}" /tmp/command.sh

if is_debug
then
  debug "Leaving previous versions of the builder images intact"
else
  docker images -qa --filter "label=${DOCKERIMAGE}" | uniq | xargs docker inspect --format '{{ join .RepoTags " " }}' 2>/dev/null | grep -v latest | xargs docker rmi 2>/dev/null || true
fi