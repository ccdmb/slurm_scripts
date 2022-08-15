#!/usr/bin/env bash

echo_stderr() {
    echo $@ 1>&2
}

isin() {
    PARAM=$1
    shift
    for f in $@
    do
        if [[ "${PARAM}" == "${f}" ]]; then return 0; fi
    done

    return 1
}
