#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export TZ="America/Los_Angeles"

apt-get update -y
apt-get install -y tzdata build-essential sudo
source ${GITHUB_WORKSPACE}/ci_setup

$CI_ROOT/managers/ubuntu.sh

exit 0
