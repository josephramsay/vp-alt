#!/bin/bash

set -e

echo "placeholder for tests"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
MIGRATE_SCRIPT=migrate.sh
META_SCRIPT=meta.sh
. ${SCRIPT_DIR}/${META_SCRIPT}