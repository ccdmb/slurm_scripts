#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(readlink -f $0)"
DIRNAME="$(dirname ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H%M%S')"

DRY_RUN=false

source "${DIRNAME}/../lib/cli.sh"
source "${DIRNAME}/../lib/batch.sh"

VALID_SUBCOMMANDS=( fn sh )

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


read -r -d '' FN_CALL <<EOF_FN || true
$(declare -f ${FN})

NEW_JOB_ID=\$(${FN})
EOF_FN



read -r -d '' SH_CALL <<EOF_SH || true
read -r -D 
NEW_JOB_ID=\$(${SH})
EOF_SH

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login

set -euo pipefail

$(declare ${FN})

NEW_JOB_ID=\$(${FN})

$(declare -f update_dependencies)

update_dependencies "\${SLURM_JOB_ID}" "\${NEW_JOB_ID}"
EOF

SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --dependency="${DEP}")


echo "${SLURM_ID}"
