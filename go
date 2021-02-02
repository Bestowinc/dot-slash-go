#!/usr/bin/env bash

ROOT_DIR=$(cd ${0%/*}; pwd)
export ROOT_DIR

# shellcheck source=./.go/core/dsg.sh
source "$ROOT_DIR/.go/core/dsg.sh"

# Run the Bash CLI entrypoint
# cd $ROOT_DIR is used so that directory dependend logic such as git subcommands are given proper context
(cd $ROOT_DIR; ROOT_DIR="$ROOT_DIR" bcli_entrypoint "$@")
