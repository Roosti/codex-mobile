#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TEST_DIR

for test_file in "$TEST_DIR"/test_*.sh; do
  printf '\n-- %s --\n' "$(basename -- "$test_file")"
  bash "$test_file"
done

printf '\nAll tests passed.\n'
