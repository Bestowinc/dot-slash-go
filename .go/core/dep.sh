#!/usr/bin/env bash

ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel)}"
DEP_FILE=${DEP_FILE:-"$ROOT_DIR/.go/.dep"}
BIN_DIR=${BIN_DIR:-"$ROOT_DIR/.go/.bin"}
PATH=$BIN_DIR:$PATH

# shellcheck source=.go/core/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# dep updates/installs binaries to $BIN_DIR or checks the existence of a CLI tool in $PATH
dep() {
  # .dep manifest arguments
  ############################################################################
  local name="$1" # name of the command line tool
  local varg      # argument to call returning vesrion number
  local v_ref     # minimum expected version
  local os_ref    # pattern used to curl the correct tar file
  local url       # envsubst pattern used to seed the download link
  local tar_path  # if file is not in root directory, provide location of file
  ############################################################################
  {
    read -r varg
    read -r v_ref
    read -r os_ref
    read -r url
    read -r tar_path
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
    warn "installing ${name} v${v_ref}..."
    get_dep "$name" "$url" "$tar_path"
  fi

  # call/eval cli tool with version
  local eval_version
  eval_version="$(version "$name" "$varg")"

  # check if local version is out of date for supported tools,  warn if out of date
  if [ -n "$eval_version" ]; then
    local latest_return=0
    is_latest "$name" "$v_ref" "$eval_version" || latest_return=$?
    if [[ "$latest_return" == 3 ]]; then
      warn "local version: ${eval_version}"
      warn "expected version: ${v_ref}"
      warn "$name v${eval_version} is outdated"
      warn "installing ${name} v${v_ref}..."
      get_dep "$name" "$url" "$tar_path"
    fi
  else
    fail "unable to install ${name} v${v_ref}"
  fi
}

# read_manifest reads through and returns .dep manifest arguments for a given tool
read_manifest() {
  local name="$1"
  local dep_file="$2"
  local found=0
  local varg
  local v_ref
  local darwin_ref
  local linux_ref
  local url
  local tar_path

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
    v_ref:) v_ref="$val" ;;
    darwin_ref:) darwin_ref="$val" ;;
    linux_ref:) linux_ref="$val" ;;
    url:) url="$val" ;;
    tar_path:) tar_path="$val" ;;
    "}")
      {
        if [[ "$found" == 0 ]]; then
          unset varg v_ref darwin_ref linux_ref url tar_path
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
        tar_path="$(eval echo "${tar_path:-}")"

      }
      ;;
    esac
  }; done <"$dep_file"
  # return defs
  echo "${varg:-}"
  echo "${v_ref:-}"
  echo "${os_ref:-}"
  echo "${url:-}"
  echo "${tar_path:-}"
  echo "${found:-}"
}

# get_det curls a tar.gz url and untars the result to $BIN_DIR
get_dep() {
  local name="$1"
  local url="$2"
  local tar_path="${3:-$1}"
  local dir_nesting="${tar_path//[^\/]/}"
  # count the # of directories to strip by amount of forward slashes
  local strip_count=${#dir_nesting}

  curl -SLk "${url}" | tar xvz --strip-components "$strip_count" -C "$BIN_DIR" "$tar_path"
}

# version invites a tool's '--version' subcommand to return a string's stdout and stderr output to look
# for a semantic vesrion
version() {
  local name="$1"
  local varg="$2"
  local eval_version
  # pull a valid semver value from the output, this should include
  # multiline --version calls such as "gh --version"
  if ! eval_version=$($name "$varg" 2>&1 | grep -Eo "([0-9]+\.){1,}[0-9](-\w+)?" | head -1); then
    fail "\"$name $varg\" does not produce a version number!"
  fi
  echo "$eval_version"
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

  if [[ "$latest_version" != "$eval_version" ]]; then
    return 3
  fi
  return 0
}

verify_path() {
  local which_err_code=0
  command -v "$1" 1>/dev/null || which_err_code=$?

  if [[ "${which_err_code}" == 1 ]]; then
    # call the error function
    fail "\ndep: $1 not found in \$PATH, should it be added to \"$BIN_DIR\"?"
  fi
}
