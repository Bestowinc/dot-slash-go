#!/usr/bin/env bash

ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel)}"

# shellcheck source=.go/core/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

function dsg_trim_whitespace() {
  # Function courtesy of http://stackoverflow.com/a/3352015
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}" # remove leading whitespace characters
  var="${var%"${var##*[![:space:]]}"}" # remove trailing whitespace characters
  echo -n "$var"
}

function dsg_show_header() {
  echo -e "$(dsg_trim_whitespace "$(cat "$1/.name")")"
}

function dsg_entrypoint() {
  local cli_entrypoint
  cli_entrypoint=$(basename "$0")

  # Locate the correct command to execute by looking through the app directory
  # for folders and files which match the arguments provided on the command line.
  local cmd_file
  cmd_file="$ROOT_DIR/.go/"
  local cmd_arg_start
  cmd_arg_start=1
  while [[ -d "$cmd_file" && $cmd_arg_start -le $# ]]; do

    # If the user provides help as the last argument on a directory, then
    # show them the help for that directory rather than continuing
    if [[ "${!cmd_arg_start}" == "help" || "${!cmd_arg_start}" == "--help" ]]; then
      # Strip off the "help" portion of the command
      local args
      args=("$@")
      unset "args[$((cmd_arg_start - 1))]"
      args=("${args[@]}")

      dsg_help "$0" "${args[@]}"
      exit 101
    fi

    cmd_file="$cmd_file/${!cmd_arg_start}"
    cmd_arg_start=$((cmd_arg_start + 1))
  done

  # Place the arguments for the command in their own list
  # to make future work with them easier.
  local cmd_args
  cmd_args=("${@:cmd_arg_start}")

  # If we hit a directory by the time we run out of arguments, then our user
  # hasn't completed their command, so we'll show them the help for that directory
  # to help them along.
  if [ -d "$cmd_file" ]; then
    dsg_help "$0" "$@"
    exit 101
  fi

  # If we didn't couldn't find the exact command the user entered then warn them
  # about it, and try to be helpful by displaying help for that directory.
  if [[ ! -f "$cmd_file" ]]; then
    dsg_help "$0" "${@:1:$((cmd_arg_start - 1))}"
    echo >&2 -e "${COLOR_RED}We could not find the command ${COLOR_CYAN}$cli_entrypoint ${*:1:$cmd_arg_start}${COLOR_NORMAL}"
    echo >&2 -e "To help out, we've shown you the help docs for ${COLOR_CYAN}$cli_entrypoint ${*:1:$((cmd_arg_start - 1))}${COLOR_NORMAL}"
    exit 101
  fi

  # If --help is passed as one of the arguments to the command then show
  # the command's help information.
  arg_i=0 # We need the index to be able to strip list indices
  for arg in "${cmd_args[@]}"; do
    if [[ "${arg}" == "--help" && -f "$cmd_file.help" ]]; then
      # Strip off the `--help` portion of the command
      unset "cmd_args[$arg_i]"
      cmd_args=("${cmd_args[@]}")

      # Pass the result to the help script for interrogation
      dsg_help "$0" "${@:1:$((cmd_arg_start - 1))}" "${cmd_args[@]}"
      exit 101
    fi
    arg_i=$((arg_i + 1))
  done

  # Run the command and capture its exit code for introspection
  "$cmd_file" "${cmd_args[@]}"
  EXIT_CODE=$?

  # If the command exited with an exit code of 101 (our "show help" code)
  # then show the help documentation for the command.
  if [[ $EXIT_CODE == 101 ]]; then
    dsg_help "$0" "$@"
  fi

  # Exit with the same code as the command
  exit $EXIT_CODE
}

function dsg_help() {
  local cli_entrypoint
  cli_entrypoint=$(basename "$1")

  # If we don't have any additional help arguments, then show the app's header as well.
  if [ $# == 1 ]; then
    dsg_show_header "$ROOT_DIR/.go"
  fi

  # Locate the correct level to display the helpfile for, either a directory
  # with no further arguments, or a command file.
  local help_file
  help_file="$ROOT_DIR/.go/"
  local help_arg_start
  help_arg_start=2
  while [[ -d "$help_file" && $help_arg_start -le $# ]]; do
    help_file="$help_file/${!help_arg_start}"

    help_arg_start=$((help_arg_start + 1))
  done

  # If we've got a directory's helpfile to show, then print out the list of
  # commands in that directory along with its help content.
  if [[ -d "$help_file" ]]; then
    echo -e "${COLOR_GREEN}$cli_entrypoint ${COLOR_CYAN}${*:2:$((help_arg_start - 1))} ${COLOR_NORMAL}"

    # If there's a help file available for this directory, then show it.
    if [[ -f "$help_file/.help" ]]; then
      cat "$help_file/.help"
      echo ""
    fi

    echo -e "${COLOR_MAGENTA}Commands${COLOR_NORMAL}"
    echo ""

    for file in "$help_file"/*; do
      cmd=$(basename "$file")

      # Don't show hidden files as available commands
      if [[ "$cmd" != .* && "$cmd" != *.* ]]; then
        echo -en "${COLOR_GREEN}$cli_entrypoint ${COLOR_CYAN}${*:2:$((help_arg_start - 1))} $cmd ${COLOR_NORMAL}"

        if [[ -f "$file.usage" ]]; then
          dsg_trim_whitespace "$(cat "$file.usage")"
          echo ""
        elif [[ -d "$file" && -f "$file.usage" ]]; then
          dsg_trim_whitespace "$(cat "$file/.usage")"
          echo ""
        elif [[ -d "$file" && ! -f "$file.usage" ]]; then
          echo -e "${COLOR_MAGENTA}...${COLOR_NORMAL}"
        else
          echo ""
        fi
      fi
    done

    exit 0
  fi

  echo -en "${COLOR_GREEN}$cli_entrypoint ${COLOR_CYAN}${*:2:$((help_arg_start - 1))} ${COLOR_NORMAL}"
  if [[ -f "$help_file.usage" ]]; then
    dsg_trim_whitespace "$(cat "$help_file.usage")"
    echo ""
  else
    echo ""
  fi

  if [[ -f "$help_file.help" ]]; then
    cat "$help_file.help"
    echo ""
  fi
}
