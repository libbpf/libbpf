#!/bin/bash

PHASES=(${@:-SETUP RUN RUN_ASAN CLEANUP})
DEBIAN_RELEASE="${DEBIAN_RELEASE:-testing}"
CONT_NAME="${CONT_NAME:-debian-$DEBIAN_RELEASE-$RANDOM}"
DOCKER_EXEC="${DOCKER_EXEC:-docker exec -it $CONT_NAME}"
DOCKER_RUN="${DOCKER_RUN:-docker run}"
REPO_ROOT="${REPO_ROOT:-$PWD}"
ADDITIONAL_DEPS=(clang)

function info() {
    echo -e "\033[33;1m$1\033[0m"
}

set -e

source "$(dirname $0)/travis_wait.bash"

for phase in "${PHASES[@]}"; do
    case $phase in
        SETUP)
            info "Setup phase"
            info "Using Debian $DEBIAN_RELEASE"
	    docker pull debian:$DEBIAN_RELEASE
            info "Starting container $CONT_NAME"
            $DOCKER_RUN -v $REPO_ROOT:/build:rw \
                        -w /build --privileged=true --name $CONT_NAME \
			-dit --net=host debian:$DEBIAN_RELEASE /bin/bash
            $DOCKER_EXEC bash -c "echo deb-src http://deb.debian.org/debian $DEBIAN_RELEASE main >>/etc/apt/sources.list"
            $DOCKER_EXEC apt-get -y update
            $DOCKER_EXEC apt-get -y build-dep libelf-dev
            $DOCKER_EXEC apt-get -y install libelf-dev
            $DOCKER_EXEC apt-get -y install "${ADDITIONAL_DEPS[@]}"
            ;;
        RUN|RUN_CLANG)
            if [[ "$phase" = "RUN_CLANG" ]]; then
                ENV_VARS="-e CC=clang -e CXX=clang++"
            fi
            docker exec $ENV_VARS -it $CONT_NAME mkdir build
            $DOCKER_EXEC make CFLAGS='-Werror' -C ./src -B OBJDIR=../build
            $DOCKER_EXEC rm -rf build
            ;;
        RUN_ASAN|RUN_CLANG_ASAN)
            if [[ "$phase" = "RUN_CLANG_ASAN" ]]; then
                ENV_VARS="-e CC=clang -e CXX=clang++"
            fi
            docker exec $ENV_VARS -it $CONT_NAME mkdir build
            $DOCKER_EXEC make CFLAGS='-Werror -Db_sanitize=address,undefined' -C ./src -B OBJDIR=../build
            $DOCKER_EXEC rm -rf build
            ;;
        CLEANUP)
            info "Cleanup phase"
            docker stop $CONT_NAME
            docker rm -f $CONT_NAME
            ;;
        *)
            echo >&2 "Unknown phase '$phase'"
            exit 1
    esac
done
