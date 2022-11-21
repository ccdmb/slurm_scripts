#!/usr/bin/env bash

set -euo pipefail

SCRIPT="$(readlink -f $0)"
DIRNAME="$(dirname ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H:%M:%S')"

# Set defaults
VERSION="v0.0.1"
DRY_RUN=false
PACK=false
RESUME=
MODULES=( )
CONDAENV=

INFILE=/dev/stdin

NTASKS_PER_NODE=
NODES=
NTASKS=
CPUS_PER_TASK=

SLURM_STDOUT_SET=false
SLURM_STDOUT_DEFAULT="%x-%A_%4a.stdout"
SLURM_STDERR_SET=false
SLURM_STDERR_DEFAULT="%x-%A_%4a.stderr"
SLURM_LOG="%x-%A_%4a.log"
SLURM_EXPORT_SET=false
SLURM_EXPORT_DEFAULT="NONE"
SLURM_ACCOUNT_SET=false
SLURM_ACCOUNT_DEFAULT="${PAWSEY_PROJECT:-UNSET}"
SLURM_PARTITION_SET=false
SLURM_PARTITION_DEFAULT="work"
SLURM_JOB_NAME_SET=false
SLURM_JOB_NAME_DEFAULT=$(basename "${SCRIPT%%.*}")

# This sets -x
DEBUG=false

source "${DIRNAME}/../lib/general.sh"
source "${DIRNAME}/../lib/cli.sh"
source "${DIRNAME}/../lib/batch.sh"

usage() {
    echo -e "USAGE:
${SCRIPT}
"
}

usage_err() {
    usage 1>&2
    echo_stderr -e "
Run \`${SCRIPT} --batch-help\` for extended usage information."
}


help() {
    echo -e "
This script wraps SLURM job-arrays up in a more convenient script to run a series of commands.

It requires SLURM installed in your environment.

Parameters:
  --account=GROUP -- Which account should the slurm job be submitted under. DEFAULT: ${SLURM_ACCOUNT_DEFAULT}
  --export={[ALL,]<environment_variables>|ALL|NONE} Default ${SLURM_EXPORT_DEFAULT} as suggested by pawsey.
  --partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: ${SLURM_PARTITION_DEFAULT}
  --output -- The output filename of the job stdout. default "${SLURM_STDOUT_DEFAULT}"
  --error -- The output filename of the job stderr. default "${SLURM_STDOUT_DEFAULT}"
  --batch-log -- Log the job exit codes here so we can restart later. default "${SLURM_LOG}"
  --batch-resume -- Resume the jobarray, skipping previously successful jobs according to the file provided here. <(cat *.log) is handy here.
  --batch-pack -- Pack the job so that multiple tasks run per job array job. Uses the value of --ntasks to determine how many to run per job.
  --batch-dry-run -- Print the command that will be run and exit.
  --batch-module -- Include this module the sbatch script. Can be specified multiple times.
  --batch-condaenv -- Load this conda environment.
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.
  --batch-version -- Print the version and exit.

All other parameters, flags and arguments before '--' are passed to sbatch as is.
See: https://slurm.schedmd.com/sbatch.html

Note: you can't provide the --array flag, as this is set internally and it will raise an error.


For more complex scripts, I'd suggest wrapping it in a separate script.
Note that unlike GNU parallel and srun, we don't support running functions.
"
}


SLURM_ARGS=( )

# Here we catch our special parameters and collect the rclone ones
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --batch-module)
            check_param "--batch-module" "${2:-}"
            MODULES+=( "${2}" )
            shift 2
            ;;
        --batch-condaenv)
            check_param "--batch-condaenv" "${2:-}"
            CONDAENV="${2}"
            shift 2
            ;;
        --batch-log)
            check_param "--batch-log" "${2:-}"
            SLURM_LOG="${2}"
            shift 2
            ;;
        --batch-resume)
            check_no_default_param "--batch-resume" "${RESUME:-}" "${2:-}"
            RESUME="${2}"
            shift 2
            ;;
        --batch-pack)
            PACK=true
            shift
            ;;
        --batch-dry-run)
            DRY_RUN=true
            shift
            ;;
        --batch-debug)
            DEBUG=true
            shift # past argument
            ;;
        --batch-help)
            usage
            help
            exit 0
            ;;
        --batch-version)
            echo "${VERSION}"
            exit 0
            ;;
        -a|--array|-a=*|--array=*)
            echo_stderr "ERROR: We handle the --array parameter ourselves, you cant set it"
            echo_stderr "ERROR: Remove the \`--array\` parameter."
            exit 1
            ;;
        --ntasks-per-core*|--ntasks-per-gpu*|--ntasks-per-socket*)
            echo_stderr "ERROR: We cannot handle the --ntasks-per flags currently"
            echo_stderr "ERROR: Please set the number of tasks separately or write your own script."
            exit 1
        ;;
        --parsable)
            # We add this already
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
        if isin "$1" "${VALID_SBATCH_FLAGS[@]}"
        then
            SLURM_ARGS+=( "$1" )
            shift
            continue
        fi

        THIS_ARG="${1}"
        NEXT_ARG="${THIS_ARG#*=}"
        THIS_ARG="${THIS_ARG%%=*}"

        if [ "${THIS_ARG}" != "${NEXT_ARG}" ]
        then
            # This means there was an = sign
            SKIP=1
        elif [[ ! "${2:-}" = "-"* ]]
        then
            NEXT_ARG="${2:-}"
            SKIP=2
        else
            NEXT_ARG=""
            SKIP=1
        fi

        # Having -n in an array causes issues for some reason
        THIS_ARG=$(promote_sbatch_arg "${THIS_ARG}")

        if ! isin "${THIS_ARG}" ${VALID_SBATCH_FLAGS_OPTIONAL_VALUE[@]} ${VALID_SBATCH_ARGS[@]}
        then
            echo_stderr "ERROR: Got an invalid parameter ${1}"
            exit 1
        fi

        if ( isin "${THIS_ARG}" "${VALID_SBATCH_ARGS[@]}" ) && [ -z "${NEXT_ARG:-}" ]
        then
            echo_stderr "ERROR: ${THIS_ARG} expects a value."
            exit 1
        fi

        case "${THIS_ARG}" in
            --export)
                SLURM_EXPORT_SET=true
                ;;
            -A|--account)
                SLURM_ACCOUNT_SET=true
                ;;
            -p|--partition)
                SLURM_PARTITION_SET=true
                ;;
            -o|--output)
                SLURM_STDOUT_SET=true
                ;;
            -e|--error)
                SLURM_STDERR_SET=true
                ;;
            -n|--ntasks)
                NTASKS="${NEXT_ARG}"
                ;;
            -N|--nodes)
                NODES="${NEXT_ARG}"
                ;;
            --ntasks-per-node)
                NTASKS_PER_NODE="${NEXT_ARG}"
                ;;
            -c|--cpus-per-task)
                CPUS_PER_TASK="${NEXT_ARG}"
                ;;
            -J|--job-name)
                SLURM_JOB_NAME_SET=true
                ;;
        esac

        if [ ! -z "${NEXT_ARG:-}" ]
        then
            SLURM_ARGS+=( "${THIS_ARG}=${NEXT_ARG}" )
        else
            SLURM_ARGS+=( "${THIS_ARG}" )
        fi

        shift "${SKIP}"
        ;;
    esac
done

if [ "${DEBUG:-}" = "true" ]
then
    set -x
fi

if [ "${DRY_RUN}" = "false" ]
then
    # Check if we've got sbatch
    if ! which sbatch > /dev/null
    then
        echo_stderr "This script requires sbatch to be available on your path."
        exit 1
    fi
fi


# Set a couple of default slurm parameters if they werent given

if [ "${SLURM_STDOUT_SET}" = false ] && [ "${SLURM_STDERR_SET}" = false ]
then
    SLURM_ARGS+=( "--output=${SLURM_STDOUT_DEFAULT}" )
    SLURM_ARGS+=( "--error=${SLURM_STDERR_DEFAULT}" )
fi

if [ "${SLURM_EXPORT_SET}" = false ]
then
    SLURM_ARGS+=( "--export=${SLURM_EXPORT_DEFAULT}" )
fi

if [ "${SLURM_ACCOUNT_SET}" = false ]
then
    SLURM_ARGS+=( "--account=${SLURM_ACCOUNT_DEFAULT}" )
fi

if [ "${SLURM_PARTITION_SET}" = false ]
then
    SLURM_ARGS+=( "--partition=${SLURM_PARTITION_DEFAULT}" )
fi

if [ "${SLURM_JOB_NAME_SET}" = false ]
then
    SLURM_ARGS+=( "--job-name=${SLURM_JOB_NAME_DEFAULT}" )
fi

if [ "${PACK}" = true ] && [ -z "${NTASKS:-}" ]
then
    if [ ! -z "${NTASKS_PER_NODE:-}" ]
    then
        if [ ! -z "${NODES:-}" ]
        then
            NTASKS=$(( "${NTASKS_PER_NODE:-}" * "${NODES:-}" ))
        else
            echo_stderr "If you provide --ntasks-per-node you must also provide --nodes"
            exit 1
        fi
    fi
fi

# Reads stdin or file into an array of lines.
# Note that cat will remove any trailing newlines
CMDS=$(cat "${INFILE}" | sort)

# We want to fail early on empty lines or duplicate commands so that everything runs as expected

# The grep removes any empty lines and lines starting with a # (comments)
CMDS_SPACE=$(echo "${CMDS}" | { grep -v '^[[:space:]]*$\|^[[:space:]]*#' || true; } | sort)

if ! diff <(echo "${CMDS}") <(echo "${CMDS_SPACE}") 1>&2
then
    echo_stderr 'ERROR: The commands given contain an empty line or a line starting with # (a comment)'
    echo_stderr 'ERROR: See the diff output above for locations'
    exit 1
fi

# The sort removes any duplicate commands
CMDS_UNIQUE=$(echo "${CMDS}" | sort -u)

if ! diff <(echo "${CMDS}") <(echo "${CMDS_UNIQUE}") 1>&2
then
    echo_stderr 'ERROR: The commands given contain duplicate commands'
    echo_stderr 'ERROR: See the diff output above for locations'
    exit 1
fi
unset CMDS_SPACE
unset CMDS_UNIQUE

NJOBS=$(echo "${CMDS}" | { grep -v '^[[:space:]]*$' || true; } | wc -l)

if [ "${NJOBS}" -eq 0 ]
then
    echo_stderr "ERROR: We didnt get any tasks to run!"
    exit 1
fi

if [ ! -z "${RESUME:-}" ]
then
    RESUME_CLEANED=$(cat "${RESUME}" | grep -v "^[[:space:]]*$\|^[[:space:]]*#" | sort -u)
    MIN_NCOLS=$(echo "${RESUME_CLEANED}" | awk -F'\t' 'BEGIN {MINNF=0} {if (NR == 1) {MINNF = NF}; if ( NF > 0 ) {MINNF=(MINNF < NF ? MINNF : NF)} } END {print MINNF}')
    RESUME="${RESUME_CLEANED}"
    unset RESUME_CLEANED

    if [ "${MIN_NCOLS}" -lt 4 ]
    then
        echo_stderr "ERROR: At least one entry in the file provided to --batch-resume contained ${MIN_NCOLS} columns."
        echo_stderr "ERROR: We need at least 4 columns to figure out what to do."
        exit 1
    else
        COMPLETED_CMDS="$(echo -e "${RESUME}" | awk -F '\t' '$3 == 0' | cut -d'	' -f4-)"

        # This prints anything in CMDs that isn't in COMPLETED_CMDS
        REMAINING_CMDS=$(grep -f <(echo "${COMPLETED_CMDS}") -F -v <(echo "${CMDS}") || : )

        if [ -z "$( echo '${REMAINING_CMDS}' | sed 's/[[:space:]]//g')" ]
        then
            CMDS=""
        else
            CMDS="${REMAINING_CMDS}"
        fi
        unset REMAINING_CMDS

        COMPLETED_CMDS=$(echo "${COMPLETED_CMDS}" | awk '{print "COMPLETED: " $0}')
        echo_stderr '######################################'
        echo_stderr "Skipping the following commands because they were in the file provided to --batch-resume"
        # echo stderr doesn't preserve newlines
        echo "${COMPLETED_CMDS}" 1>&2
        unset COMPLETED_CMDS
    fi
fi

NJOBS="$(echo "${CMDS}" | { grep -v '^[[:space:]]*$' || true; } | wc -l)"

if [ "${NJOBS}" -eq 0 ]
then
    echo_stderr "After filtering completed jobs there were no jobs left..."
    echo_stderr "Not submitting SLURM job"
    exit 0
fi

if [ "${PACK}" = true ]
then
    if [ -z "${NTASKS:-}" ]
    then
        echo_stderr "ERROR: If you wish to use a packed job (--batch-pack), you must provide --ntasks > 1."
        exit 1
    elif [ "${NTASKS:-}" -le 1 ]
    then
        echo_stderr "ERROR: If you wish to use a packed job (--batch-pack), you must provide --ntasks > 1."
        exit 1
    fi
    ARRAY_STR="0-$(( ${NJOBS} - 1 )):${NTASKS}"
else
    ARRAY_STR="0-$(( ${NJOBS} - 1 ))"
fi

SLURM_ARGS+=( "--array=${ARRAY_STR}" )
DIRECTIVES=$(printf "#SBATCH %s\n" "${SLURM_ARGS[@]}")


if [ "${#MODULES[@]}" -gt 0 ]
then
    MODULE_CMD="module load ${MODULES[@]}"
else
    MODULE_CMD=""
fi

if [ -z "${CONDAENV}" ]
then
    CONDAENV_CMD=""
else
    CONDAENV_CMD="conda activate '${CONDAENV}'"
fi

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login
${DIRECTIVES}

${MODULE_CMD}
${CONDAENV_CMD}
set -euo pipefail

JOBID="\${SLURM_ARRAY_JOB_ID}_\${SLURM_ARRAY_TASK_ID}"

LOG_FILE_NAME=\$(${DIRNAME}/gen_slurm_filename.py '${SLURM_LOG}')

cleanup()
{
    EXITCODE="\$?"
    rm -f -- \${LOG_FILE_NAME}.lock

    echo -e "\n"
    seff "\${JOBID}" | grep -v "WARNING: Efficiency statistics may be misleading for RUNNING jobs." || true
    echo -e "\n"

    if [ "\${EXITCODE}" -ne 0 ]
    then
        # We are putting this to stdout. stderr already has a warning from srun
        # This points to you stderr if its in a separate file
        echo -e "###########  ERROR!!! #############\n"
        echo "ERROR: srun returned a non-zero status: \${EXITCODE}."
        echo "ERROR: Please look at the error and log files to find the problem."
    fi
}

trap cleanup EXIT

# srun will inherit the resource directives from parent batch script.
srun --export=all bash -s "\${LOG_FILE_NAME}" <<'EOF_SRUN'
#!/usr/bin/env bash

set -euo pipefail

INDEX="\$(( \${SLURM_ARRAY_TASK_ID:-0} + \${SLURM_PROCID:-0} ))"

if [ "\${INDEX}" -gt $(( ${NJOBS} - 1 )) ]
then
    exit 0
fi

readarray -t CMDS <<'CMD_EOF' || true
${CMDS}
CMD_EOF

CMD="\${CMDS[\${INDEX}]}"

LOG_FILE_NAME="\${1}"

$(declare -f write_log)

actually_write_log()
{
    EXITCODE="\$?"
    write_log "\${LOG_FILE_NAME}" "\${SLURM_JOB_NAME:-\(none\)}" "\${INDEX:-0}" "\${EXITCODE}" "\${CMDS[\${INDEX}]}"
    return "\${EXITCODE}"
}

trap actually_write_log EXIT

eval "\${CMD}"
EOF_SRUN
EOF

if [ "${DRY_RUN}" = "true" ]
then
    echo "${BATCH_SCRIPT}"
else
    SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --parsable)
    echo ${SLURM_ID}
fi
