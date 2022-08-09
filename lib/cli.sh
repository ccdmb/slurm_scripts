#!/usr/bin/env bash

set -euo pipefail

echo_stderr() {
    echo $@ 1>&2
}

export -f echo_stderr

isin() {
    PARAM=$1
    shift
    for f in $@
    do
        if [[ "${PARAM}" == "${f}" ]]; then return 0; fi
    done

    return 1
}

check_positional() {
    FLAG="${1}"
    VALUE="${2}"
    if [ -z "${VALUE:-}" ]
    then
        echo_stderr "Positional argument ${FLAG} is missing."
        exit 1
    fi
    true
}

has_equals() {
    return $([[ "${1}" = *"="* ]])
}

split_at_equals() {
    IFS="=" FLAG=( ${1} )
    ONE="${FLAG[0]}"
    TWO=$(printf "=%s" "${FLAG[@]:1}")
    IFS="=" echo "${ONE}" "${TWO:1}"
}

check_no_default_param() {
    FLAG="${1}"
    PARAM="${2}"
    VALUE="${3}"
    [ ! -z "${PARAM:-}" ] && (echo_stderr "Argument ${FLAG} supplied multiple times"; exit 1)
    [ -z "${VALUE:-}" ] && (echo_stderr "Argument ${FLAG} requires a value"; exit 1)
    true
}

check_param() {
    FLAG="${1}"
    VALUE="${2}"
    [ -z "${VALUE:-}" ] && (echo_stderr "Argument ${FLAG} requires a value"; exit 1)
    true
}
