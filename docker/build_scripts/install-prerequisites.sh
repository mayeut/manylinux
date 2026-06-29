#!/bin/sh
# Install entrypoint:
#   - install bash on Alpine as most scripts require it
#   - install, update & patch ca-certificates

# Stop at any error, show all commands
set -exu

# Set build environment variables
MY_DIR=$(dirname "$0")

export LC_ALL=C

if [ "${AUDITWHEEL_POLICY#musllinux}" != "${AUDITWHEEL_POLICY}" ]; then
	apk add --no-cache bash coreutils
fi

"${MY_DIR}/install-ca-certificates.sh"
