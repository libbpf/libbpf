#!/bin/bash
set -e
set -x

apt-get update
apt-get -y build-dep libelf-dev
apt-get install -y libelf-dev

source "$(dirname $0)/travis_wait.bash"

cd $REPO_ROOT

CFLAGS="-g -O2 -Werror -Wall -fsanitize=address,undefined"
mkdir build
cc --version
make CFLAGS="${CFLAGS}" -C ./src -B OBJDIR=../build
rm -rf build
