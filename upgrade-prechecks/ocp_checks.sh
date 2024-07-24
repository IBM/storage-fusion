#!/usr/bin/env bash

# Inherit the shell variables in the subprocesses
# Useful for the -v flag
export SHELLOPTS

# https://betterdev.blog/minimal-safe-bash-script-template/

#set -Eeuo pipefail

# http://redsymbol.net/articles/unofficial-bash-strict-mode/
IFS=$'\n\t'

# shellcheck disable=2164
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1

# shellcheck disable=SC1091
source $(pwd)/utils

#trap cleanup SIGINT SIGTERM ERR EXIT
export ERRORFILE=$(mktemp)
trap "rm ${ERRORFILE}" EXIT

errors=0
# Flags
INFO=1
CHECKS=1
PRE=0
SSH=1
LIST=0
SINGLE=0
RESULTS_ONLY=0
SCRIPT_PROVIDED=''
RESTART_THRESHOLD=${RESTART_THRESHOLD:=10} #arbitray

parse_params "$@"
setup_colors

main() {
  # Check if only list is needed
  if [ "${LIST}" -ne 0 ]; then
    msg "${GREEN}Available scripts:${NOCOLOR}"
    find checks/ info/ pre/ ssh/ -type f | sort -n
    exit 0
  else
    # Check binaries availability
    for i in oc yq jq curl column; do
      check_command ${i}
    done
    
      # If only checks are needed:
      if [ "${CHECKS}" -gt 0 ]; then
        msg "Running basic health checks as ${GREEN}${OCUSER}${NOCOLOR}"
        for check in ./checks/*; do
          # Refresh error count before execution
          export errors=$(expr $(cat ${ERRORFILE}) + 0)
          # shellcheck disable=SC1090,SC1091
          if [ "${RESULTS_ONLY}" -gt 0 ]; then
            "${check}" &>/dev/null
            case $? in
            0 | 1) msg "${check:2} ${GREEN}PASS${NOCOLOR}" ;;
            2) msg "${check:2} ${RED}FAIL${NOCOLOR}" ;;
            3) msg "${check:2} ${ORANGE}SKIPPED${NOCOLOR}" ;;
            4) msg "${check:2} ${YELLOW}UNKNOWN${NOCOLOR}" ;;
            *) msg "${check:2} ${RED}UNKNOWN RETURN CODE${NOCOLOR}" ;;
            esac
          else
            "${check}"
          fi
        done
      fi
      
  fi
  export errors=$(expr $(cat ${ERRORFILE}) + 0)
  if [ ${errors} -gt 0 ]; then
    die "${RED}Total issues found: ${errors}${NOCOLOR}"
  else
    msg "${GREEN}No issues found${NOCOLOR}"
  fi
}

main "$@"
