#!/usr/bin/env bash

set -eof pipefail

ROOT_DIR="${ROOT_DIR:-.}"
DEP_FILE=${DEP_FILE:-"$ROOT_DIR/.go/.dep"}
BIN_DIR=${BIN_DIR:-"$ROOT_DIR/.go/.bin"}
PATH=$BIN_DIR:$PATH

# shellcheck source=.go/core/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# dep updates/installs binaries to $BIN_DIR or checks the existence of a CLI tool in $PATH
dep() {
  # .dep manifest arguments
  #######################################################
  local name="$1" # name of the command line tool
  local varg      # argument to call returning vesrion number
  local vnum      # minimum expected version
  local os_ref    # pattern used to curl the correct tar file
  local url       # envsubst pattern used to seed the download link
  local tar_dir   # if file is not in root directory, provide location of file
  #######################################################
  {
    read -r varg
    read -r vnum
    read -r os_ref
    read -r url
    read -r tar_dir
    read -r found
  } <<<"$(read_manifest "$name" "$DEP_FILE")"

  if [[ "$found" == 0 ]]; then
    # shellcheck disable=SC2046
    return $(verify_path "$name")
  fi

  if [ ! -d "$BIN_DIR" ]; then
    mkdir "$BIN_DIR"
  fi

  if [ ! -s "$BIN_DIR/$name" ]; then
    # attempt to install the tool if supported
    warn "installing ${name} v${vnum}..."
    get_dep "$name" "$url" "$tar_dir"
  fi

  # call/eval cli tool with version
  local eval_version
  eval_version="$(version "$name" "$varg")"

  # check if local version is out of date for supported tools,  warn if out of date
  if [ -n "$eval_version" ]; then
    is_latest "$name" "$vnum" "$eval_version"
    if [[ $? == 3 ]]; then
      warn "$name v${eval_version} is outdated"
      warn "installing ${name} v${vnum}..."
      get_dep "$name" "$url" "$tar_dir"
    fi
  else
    fail "unable to install ${name} v${vnum}"
  fi
}

# read_manifest reads through and returns .dep manifest arguments for a given tool
read_manifest() {
  local name="$1"
  local dep_file="$2"
  local found=0
  local varg
  local vnum
  local darwin_ref
  local linux_ref
  local url
  local tar_dir

  while read -r key val; do {
    case "$key" in
    "{") {
      if [[ "$found" == 1 ]]; then
        break
      fi
    } ;;
    name:) {
      if [[ "$val" == "$name" ]]; then
        found=1
      fi
    } ;;
    varg:) varg="$val" ;;
    vnum:) vnum="$val" ;;
    darwin_ref:) darwin_ref="$val" ;;
    linux_ref:) linux_ref="$val" ;;
    url:) url="$val" ;;
    tar_dir:) tar_dir="$val" ;;
    "}")
      {
        if [[ "$found" == 0 ]]; then
          unset varg vnum darwin_ref linux_ref url tar_dir
          continue # keep iterating if name match not found
        fi

        # return the *_ref for relevant OS
        local os_ref
        case "$OSTYPE" in
        "linux-gnu"*) os_ref=$linux_ref ;;
        "darwin"*) os_ref=$darwin_ref ;;
        *) fail "UNKNOWN OS: $OSTYPE" ;;
        esac
        url="$(eval echo "$url")"
        tar_dir="$(eval echo "$tar_dir")"

      }
      ;;
    esac
  }; done <"$dep_file"
  # return defs
  echo "$varg"
  echo "$vnum"
  echo "$os_ref"
  echo "$url"
  echo "$tar_dir"
  echo "$found"
}

# get_det curls a tar.gz url and untars the result to $BIN_DIR
get_dep() {
  local name="$1"
  local url="$2"
  local tar_dir="${3:-$1}"
  local dir_nesting="${tar_dir//[^\/]/}"
  # count the # of directories to strip by amount of forward slashes
  local strip_count=${#dir_nesting}

  curl -SLk "${url}" | tar xvz --strip-components "$strip_count" -C "$BIN_DIR" "$tar_dir"
}

# version invites a tool's '--version' subcommand to return a string's stdout and stderr output to look
# for a semantic vesrion
version() {
  local name="$1"
  local varg="$2"
  # pull a valid semver value from the output, this should include
  # multiline --version calls such as "gh --version"
  echo "$($name $varg)"
  if ! vnum=$($name "$varg" 2>&1 | grep -Eo "(\d+\.){1,}\d(-\w+)?"); then
    fail "\"$name $varg\" does not produce a version number!"
  fi
  echo "$vnum"
}

# is_latest returns an exit code of three if a tool's semantic version is less than the one listed in the dep file
is_latest() {
  local name="$1"
  local expected_version="$2"
  local eval_version="$3"
  # expected: $1 actual $2
  # sort -V means sort by semantic version and return latest version
  latest_version=$(echo -e "$expected_version\n$eval_version" |
    sed -E "s/([0-9]+\.[0-9]+\.[0-9]+$)/\1\.99999/" |
    sort -V -r | sed s/\.99999$// |
    head -n 1)

  if [ "$latest_version" != "$eval_version" ]; then
    return 3
  fi
  return 0
}

verify_path() {
  command -v "$1" 1>/dev/null || which_err_code=$?

  if [[ "${which_err_code}" -eq 1 ]]; then
    # call the error function
    fail "\ndep: $1 not found in \$PATH, should it be added to $BIN_DIR?"
  fi
}
