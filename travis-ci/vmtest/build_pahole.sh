#!/bin/bash

set -eu

source $(cd $(dirname $0) && pwd)/helpers.sh

CWD=$(pwd)
REPO_PATH=$1
PAHOLE_ORIGIN=${PAHOLE_ORIGIN:-https://git.kernel.org/pub/scm/devel/pahole/pahole.git}
PAHOLE_BRANCH=${PAHOLE_BRANCH:-master}

travis_fold start build_pahole "Building pahole ${PAHOLE_ORIGIN} ${PAHOLE_BRANCH}"

mkdir -p ${REPO_PATH}
cd ${REPO_PATH}
git init
git remote add origin ${PAHOLE_ORIGIN}
git fetch origin
git checkout ${PAHOLE_BRANCH}

# temporary work-around to bump pahole to 1.22 before it is officially released
sed -i 's/DDWARVES_MINOR_VERSION=21/DDWARVES_MINOR_VERSION=22/' CMakeLists.txt

mkdir -p build
cd build
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -D__LIB=lib ..
make -j$((4*$(nproc))) all
sudo make install

export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:/usr/local/lib
ldd $(which pahole)
pahole --version

travis_fold end build_pahole
