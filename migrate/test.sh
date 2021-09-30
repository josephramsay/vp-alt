#!/bin/bash

set -e

echo 'Running Tests'
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PY_TEST_SCRIPT=test/test_migration.py

# Run the migration test script
python3 ${SCRIPT_DIR}/${PY_TEST_SCRIPT}