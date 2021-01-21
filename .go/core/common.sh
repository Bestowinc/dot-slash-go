#!/usr/bin/env bash

#######################################################
# Variables
#######################################################
export COLOR_BLACK="\033[30m"
export COLOR_RED="\033[31m"
export COLOR_GREEN="\033[32m"
export COLOR_YELLOW="\033[33m"
export COLOR_BLUE="\033[34m"
export COLOR_MAGENTA="\033[35m"
export COLOR_CYAN="\033[36m"
export COLOR_LIGHT_GRAY="\033[37m"
export COLOR_DARK_GRAY="\033[38m"
export COLOR_NORMAL="\033[39m"

#######################################################
# Functions
#######################################################
export COLOR_INFO="${COLOR_YELLOW}"
export COLOR_WARN="${COLOR_MAGENTA}"
export COLOR_ERROR="${COLOR_RED}"
export COLOR_SUCCESS="${COLOR_GREEN}"

function info {
  echo -e "${COLOR_INFO}$*${COLOR_NORMAL}" >&2 2>&1
}

function infoln {
  echo -e "${COLOR_INFO}$*${COLOR_NORMAL}\n" >&2 2>&1
}

function warn {
  echo -e "${COLOR_WARN}$*${COLOR_NORMAL}" >&2 2>&1
}

function error {
  echo -e "${COLOR_ERROR}ERROR:$*${COLOR_NORMAL}" 1>&2
}

function fail {
  echo -e "${COLOR_ERROR}$*${COLOR_NORMAL}" 1>&2
  exit 2
}

function success {
  echo -e "${COLOR_SUCCESS}$*${COLOR_NORMAL}" >&2 2>&1
}

# https://stackoverflow.com/questions/1527049/how-can-i-join-elements-of-an-array-in-bash
function join_by {
  local d=$1
  shift
  local f=$1
  shift
  printf %s "$f" "${@/#/$d}"
}
