#!/usr/bin/env bash

ROOT_DIR="$(dirname "$(pwd)/$0")"
export ROOT_DIR

# shellcheck source=./.go/core/bash-cli.inc.sh
. ".go/core/bash-cli.inc.sh"
# Run the Bash CLI entrypoint
bcli_entrypoint "$@"
