#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(readlink -f $0)"
DIRNAME="$(dirname ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H%M%S')"

DRY_RUN=false

source "${DIRNAME}/../lib/cli.sh"
source "${DIRNAME}/../lib/batch.sh"

VALID_SUBCOMMANDS=( fn sh str )

usage() {
    echo -e "USAGE:
${SCRIPT}
"
}


usage_err() {
    usage 1>&2
    echo_stderr -e "
Run \`${SCRIPT} --batch-help\` for extended usage information.

lift_dep fn <fn> dependency
lift_dep sh <./cmd|-> dependency
"
}

help() {
    echo -e ""
}

if [ "${#}" -eq 0 ]
then
    usage
elif [ "${#}" -ne 3 ]
then
    usage_err
fi


get_fn() {
    read -r -d '' CALL <<EOF_FN || true
$(declare -f ${1})
NEW_JOB_ID=$(${1})
EOF_FN
}

get_sh() {
    read -r -d '' CALL <<EOF_SH || true
read -r -d '' INNER < <(cat "${1}")
NEW_JOB_ID=$(echo "${INNER}" | bash)
EOF_SH
}

get_str() {
    read -r -d '' CALL <<EOF_STR || true
NEW_JOB_ID=$(source "${1}")
EOF_STR
}


SUBCOMMAND="${1}"
shift
DEPENDENT="${1}"
shift
CMD="${@}"

if ! isin "${SUBCOMMAND}" "${VALID_SUBCOMMANDS[@]}"
then
    echo_stderr "ERROR: the first argument must be one of ${VALID_SUBCOMMANDS[@]}"
    usage_err
    exit 1
fi

if [[ ! "${DEPENDENT}" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]
then
    echo_stderr "ERROR: the second argument ('${DEPENDENT}') is not an integer"
    usage_err
    exit 1
fi

case "${SUBCOMMAND}" in
    fn)
        CALL=$(get_fn "${CMD}")
        ;;
    sh)
        CALL=$(get_sh "${CMD}")
        ;;
    str)
        CALL=$(get_str "${CMD}")
        ;;
    *)
        echo_stderr "ERROR: this shouldn't happen"
        exit 1
        ;;
esac

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login

set -euo pipefail

# All calls are defined to set NEW_JOB_ID
${CALL}

$(declare -f update_dependencies)

# SLURM_JOB_ID is set by slurm
update_dependencies "\${SLURM_JOB_ID}" "\${NEW_JOB_ID}"
EOF

SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --dependency="${DEP}")

echo "${SLURM_ID}"
