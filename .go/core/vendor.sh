#!/usr/bin/env bash

set -eof pipefail

ADD="./go vendor add [--prefix <path>] <name> <repository> [<ref>]"
LIST="./go vendor list [<name>]"
REMOVE="./go vendor remove <name>"
UPDATE="./go vendor update <name> [<ref>]"
ROOT_DIR="${ROOT_DIR:-.}"
VENDOR_FILE=${VENDOR_FILE:-"$ROOT_DIR/.go/.git-vendor"}
VENDOR_DIR=${VENDOR_DIR:-".go/.vendor/git"}
PATH=$PATH:$(git --exec-path)

_usage() {
  cat <<EOF
Usage:
  ./go vendor --help
  $ADD
  $LIST
  $REMOVE
  $UPDATE
EOF
}

# shellcheck disable=SC1091
source git-sh-setup

require_work_tree # git-sh-setup

case "$1" in
"" | "-h" | "--help") _usage && exit ;;
esac

command="$1"
shift
case "$command" in
"add" | "list" | "remove" | "update") ;;
*) echo >&2 "error: unknown command \"$command\"" && _usage && exit 1 ;;
esac

if [ "$1" = "--prefix" ]; then
  VENDOR_DIR="$2"
  shift
  shift
fi

get_repo_default() {
  local repo="$1"
  git ls-remote --symref "$repo" HEAD | tr '\n' ' ' | awk '{print $2,$4}' | sed 's#refs/.*/##'
}

get_commit() {
  local repo="$1"
  local ref="$2"
  git ls-remote "$repo" "$ref" | awk '{print $1}'
}

add() {
  require_clean_work_tree
  if [ $# -lt 2 ]; then
    die "Incorrect options provided: $ADD"
  fi
  local name="$1"
  local repo="$2"
  local ref="$3"
  local commit
  local path

  path="$VENDOR_DIR/$(echo "$repo" | sed -E 's#^[a-zA-Z]+((://)|@)##' | sed 's#:#/#' | sed -E 's/\.git$//')"

  # check for existence of vendor file and duplicate name/path
  if [ ! -s "$VENDOR_FILE" ]; then
    grep -Eq "name:\s+$name" "$VENDOR_FILE" && die "name: $name already exists in git-vendor file"
    grep -Eq "path:\s+$path" "$VENDOR_FILE" && die "path: $path already exists in git-vendor file"
  fi

  # get the default HEAD reaf from the remote repo
  if [ -z "$ref" ]; then
    read -r ref commit <<<"$(get_repo_default "$repo")"
  else
    commit="$(get_commit "$repo" "$ref")"
  fi

  message=$(
    cat <<EOF
Add $name from $repo@$ref

git-vendor-name: $name
git-vendor-path: $path
git-vendor-repo: $repo
git-vendor-ref: $ref
git-vendor-commit: $commit
EOF
  )
  git subtree add --prefix "$path" --message "$message" "$repo" "$ref" --squash

  # append vendor file modification to same commit
  if [ ! -s "$VENDOR_FILE" ]; then
    printf "# git-vendor #\n##############" >"$VENDOR_FILE"
  fi
  cat <<EOF >>"$VENDOR_FILE"

{
	name:	$name
	path:	$path
	repo:	$repo
	ref:	$ref
	commit:	$commit
}
EOF
  git add "$VENDOR_FILE"
  git commit --amend --no-edit # amend commit now
}

list() {
  local show_only="$1"
  while read -r key val; do {
    local name
    local path
    local repo
    local ref
    local commit
    case "$key" in
    "{") {
      unset modified
      unset name
      unset path
      unset repo
      unset ref
      unset commit
    } ;;
    name:) name="$val" ;;
    path:) path="$val" ;;
    repo:) repo="$val" ;;
    ref:) ref="$val" ;;
    commit:) commit="$val" ;;
    "}")
      if [ "$repo" ]; then
        if [[ -z "$show_only" || "$show_only" = "$name" ]]; then
          printf '%s@%s:\n' "$name" "$ref"
          printf '\tpath: %s\n' "$path"
          printf '\trepo: %s\n' "$repo"
          printf '\tcommit: %s\n' "$commit"
          printf "\n"
        fi
      fi
      ;;
    esac
  }; done <"$VENDOR_FILE"

}

# update the git vendor file with a name and optional ref
update() {
  require_clean_work_tree
  if [ $# -lt 1 ]; then
    die "Incorrect options provided: $UPDATE"
  fi

  local name="$1"
  local update_ref="$2"

  local line=0
  local found
  local update_file
  local message
  # shellcheck disable=SC2094
  while read -r key val; do {
    ((line++))
    local commit
    local commit_line
    local path
    local ref_line
    local ref
    local repo
    case "$key" in
    "{") ;;
    name:) {
      if [[ "$val" == "$name" ]]; then
        found="true"
      fi
    } ;;
    ref:) {
      ref_line="$line"
      ref="$val"
    } ;;
    repo:) repo="$val" ;;
    commit:) commit_line="$line" ;;
    path:) path="$val" ;;
    "}")
      {
        if [ -z "$found" ]; then
          continue # keep iterating if name match not found
        fi

        # Make sure the dependency exists on disk
        if [ ! -d "$path" ]; then
          die "Dependency $name is missing from $path"
        elif [ -z "$repo" ]; then
          die "Reference missing for $name"
        fi

        if [ -z "$update_ref" ]; then # if no ref was provided use one present in vendor file
          update_ref="$ref"
        fi
        commit="$(get_commit "$repo" "$update_ref")"
        message=$(
          cat <<EOF
Update $name from $repo@$update_ref

git-vendor-name: $name
git-vendor-path: $path
git-vendor-repository: $repo
git-vendor-ref: $update_ref
git-vendor-commit: $commit
EOF
        )
        # replace ref if it has changed
        update_file=$(sed "${ref_line}s/^.*$/	ref: $update_ref/" "$VENDOR_FILE" | sed "${commit_line}s/^.*$/	commit: $commit/")
        break
      }
      ;;
    esac
  }; done <"$VENDOR_FILE"

  if [ -n "$update_file" ]; then
    git subtree pull --prefix "$path" --message "$message" "$repo" "$update_ref" --squash
    echo "$update_file" >"$VENDOR_FILE"
    git add "$VENDOR_FILE"
    git commit --amend --no-edit # amend commit now
  fi
}

remove() {
  # require_clean_work_tree
  if [ $# -lt 1 ]; then
    die "Incorrect options provided: $REMOVE"
  fi

  local name="$1"
  local found
  local line=0
  local update_file
  local rm_path
  # shellcheck disable=SC2094
  while read -r key val; do {
    ((line++))
    local start_line
    local end_line
    local path
    case "$key" in
    "{") start_line="$line" ;;
    name:) {
      if [[ "$val" == "$name" ]]; then
        found="true"
      fi
    } ;;
    path:) path="$val" ;;
    "}")
      end_line="$line"
      if [ -z "$found" ]; then
        continue
      fi
      # Make sure the dependency exists
      if [ ! -d "$path" ]; then
        die "Dependency $name is missing from $path"
      fi
      update_file="$(sed "${start_line},${end_line}d" "$VENDOR_FILE")"
      rm_path="$path"
      break
      ;;
    esac
  }; done <"$VENDOR_FILE"

  if [ -n "$update_file" ]; then
    echo "$update_file" >"$VENDOR_FILE"
    git add "$VENDOR_FILE"
    git rm -rf "$path"
    git commit --message "Removing $name from $rm_path"
  fi
}

# Run the command
"$command" "$@"
