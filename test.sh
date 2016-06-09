#!/bin/bash
# ---------------------------------------------------------------------------
# test.sh - HD Genome One Installation 

# Copyright 2015, DREAMgenics S.L.
# All rights reserved.

# Usage: test.sh [-h|--help]
# DEVOLPMENT NOTES:
#Check if is already installed, for cancelling installation:  local is_installed=$(yum info <PROGRAM> | grep -c '<PROGRAM>') 1-> Installed 0->Not installed
#Error Control in all statements in a function. Use "||". command || return $ERR_COD. We must deal with returned error code: (FUNCTION && echo "OK")||echo "KO"

# Revision history:
# 2015-10-01 Created by Hal
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}
VERSION="0.1"

clean_up() { # Perform pre-exit housekeeping
  return
}

error_exit() {
  echo -e "${PROGNAME}: ${1:-"Unknown Error"}" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  exit
}

signal_exit() { # Handle trapped signals
  case $1 in
    INT)
      error_exit "Program interrupted by user" ;;
    TERM)
      echo -e "\n$PROGNAME: Program terminated" >&2
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}

usage() {
  echo -e "Usage: $PROGNAME [-h|--help]"
}

help_message() {
  cat <<- _EOF_
  $PROGNAME ver. $VERSION
  Installation HD GEnome One

  $(usage)

  Options:
  -h, --help  Display this help message and exit.

  NOTE: You must be the superuser to run this script.

_EOF_
  return
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Check for root UID
if [[ $(id -u) != 0 ]]; then
  error_exit "You must be the superuser to run this script."
fi

# Parse command-line
while [[ -n $1 ]]; do
  case $1 in
    -h | --help)
      help_message; graceful_exit ;;
    -* | --*)
      usage
      error_exit "Unknown option $1" ;;
    *)
      echo "Argument $1 to process..." ;;
  esac
  shift
done

# Main logic

graceful_exit

