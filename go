#!/usr/bin/env bash

ROOT_DIR="$(dirname "$(pwd)/$0")"
export ROOT_DIR

# shellcheck source=./.go/core/bash-cli.inc.sh
source ".go/core/bash-cli.inc.sh"
# Run the Bash CLI entrypoint
ROOT_DIR="$ROOT_DIR" bcli_entrypoint "$@"
