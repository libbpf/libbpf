#!/bin/sh

# An example of a script run on VM boot.
# To execute it in TravisCI set VMTEST_SETUPCMD env var of .travis.yml in
# libbpf root folder, e.g.
# VMTEST_SETUPCMD="./${PROJECT_NAME}/travis-ci/vmtest/setup_example.sh"

if [ ! -z "${PROJECT_NAME}" ]; then
	echo "Running ${PROJECT_NAME} setup scripts..."
fi
echo "Hello, ${USER}!"
