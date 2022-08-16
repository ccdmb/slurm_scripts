#!/usr/bin/env bash

check_positional() {
    FLAG="${1}"
    VALUE="${2}"
    if [ -z "${VALUE:-}" ]
    then
        echo "ERROR: Positional argument ${FLAG} is missing." 1>&2
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
    echo "${ONE}" "${TWO:1}"
}

check_no_default_param() {
    FLAG="${1}"
    PARAM="${2}"
    VALUE="${3}"
    [ ! -z "${PARAM:-}" ] && (echo "ERROR: Argument ${FLAG} supplied multiple times" 1>&2; exit 1)
    [ -z "${VALUE:-}" ] && (echo "ERROR: Argument ${FLAG} requires a value" 1>&2; exit 1)
    true
}

check_param() {
    FLAG="${1}"
    VALUE="${2}"
    [ -z "${VALUE:-}" ] && (echo "ERROR: Argument ${FLAG} requires a value" 1>&2; exit 1)
    true
}
