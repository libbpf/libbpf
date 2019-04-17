#!/bin/bash
set -e
set -x

apt-get update
apt-get -y build-dep libelf-dev
apt-get install -y libelf-dev

source "$(dirname $0)/travis_wait.bash"

cd $REPO_ROOT

mkdir build
make CFLAGS='-Werror -Db_sanitize=address,undefined' -C ./src -B OBJDIR=../build
rm -rf build
