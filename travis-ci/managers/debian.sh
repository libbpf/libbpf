#!/bin/bash

PHASES=(${@:-SETUP RUN RUN_ASAN CLEANUP})
DEBIAN_RELEASE="${DEBIAN_RELEASE:-testing}"
CONT_NAME="${CONT_NAME:-debian-$DEBIAN_RELEASE-$RANDOM}"
ENV_VARS="${ENV_VARS:-}"
DOCKER_RUN="${DOCKER_RUN:-docker run}"
REPO_ROOT="${REPO_ROOT:-$PWD}"
ADDITIONAL_DEPS=(clang pkg-config)
CFLAGS="-g -O2 -Werror -Wall"

function info() {
    echo -e "\033[33;1m$1\033[0m"
}

function docker_exec() {
    docker exec $ENV_VARS -it $CONT_NAME "$@"
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
            docker_exec bash -c "echo deb-src http://deb.debian.org/debian $DEBIAN_RELEASE main >>/etc/apt/sources.list"
            docker_exec apt-get -y update
            docker_exec apt-get -y build-dep libelf-dev
            docker_exec apt-get -y install libelf-dev
            docker_exec apt-get -y install "${ADDITIONAL_DEPS[@]}"
            ;;
        RUN|RUN_CLANG)
            if [[ "$phase" = "RUN_CLANG" ]]; then
                ENV_VARS="-e CC=clang -e CXX=clang++"
                CC="clang"
            fi
            docker_exec mkdir build
            docker_exec ${CC:-cc} --version
            docker_exec make CFLAGS="${CFLAGS}" -C ./src -B OBJDIR=../build
            docker_exec rm -rf build
            ;;
        RUN_ASAN|RUN_CLANG_ASAN)
            if [[ "$phase" = "RUN_CLANG_ASAN" ]]; then
                ENV_VARS="-e CC=clang -e CXX=clang++"
                CC="clang"
            fi
            CFLAGS="${CFLAGS} -fsanitize=address,undefined"
            docker_exec mkdir build
            docker_exec ${CC:-cc} --version
            docker_exec make CFLAGS="${CFLAGS}" -C ./src -B OBJDIR=../build
            docker_exec rm -rf build
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
