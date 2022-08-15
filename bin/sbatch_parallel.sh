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

INFILE=/dev/stdin

NTASKS_PER_NODE=
NODES=
NTASKS=
CPUS_PER_TASK=

SLURM_STDOUT_SET=false
SLURM_STDOUT_DEFAULT="%x-%j.stdout"
SLURM_STDERR_SET=false
SLURM_STDERR_DEFAULT="%x-%j.stderr"
SLURM_LOG="%x-%j.log"
SLURM_EXPORT_SET=false
SLURM_EXPORT_DEFAULT=NONE
SLURM_ACCOUNT_SET=false
SLURM_ACCOUNT_DEFAULT="${PAWSEY_PROJECT:-UNSET}"
SLURM_PARTITION_SET=false
SLURM_PARTITION_DEFAULT="work"

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
This script wraps SLURM job-arrays up in a more convenient way to perform embarassing parallelism from a glob of files.
All

It requires SLURM installed in your environment.

Parameters:
  --account=GROUP -- Which account should the slurm job be submitted under. DEFAULT: ${SLURM_ACCOUNT_DEFAULT}
  --export={[ALL,]<environment_variables>|ALL|NONE} Default ${SLURM_EXPORT_DEFAULT} as suggested by pawsey.
  --partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: ${SLURM_PARTITION_DEFAULT}
  --output -- The output filename of the job stdout. default "${SLURM_STDOUT_DEFAULT}"
  --error -- The output filename of the job stderr. default "${SLURM_STDOUT_DEFAULT}"
  --batch-log -- Log the job exit codes here so we can restart later. default "${SLURM_LOG}"
  --batch-dry-run -- Print the command that will be run and exit.
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.

All other parameters, flags and arguments before '--' are passed to sbatch as is.
See: https://slurm.schedmd.com/sbatch.html

Note: you can't provide the --array flag, as this is set internally and it will raise an error.

For more complex scripts, I'd suggest wrapping it in a separate script.
"
}


SLURM_ARGS=( --parsable )

# Here we catch our special parameters and collect the rclone ones
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --batch-module)
            check_param "--batch-module" "${2:-}"
            MODULES=( "${MODULES[@]}" "${2}" )
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
            SLURM_ARGS=( "${SLURM_ARGS[@]}" "$1")
            shift
            continue
        fi

        THIS_ARG=( $(split_at_equals "$1") )

        if [ ${#THIS_ARG[@]} = 2 ]
        then
            NEXT_ARG="${THIS_ARG[1]}"
            THIS_ARG="${THIS_ARG[0]}"
            SKIP=1
        elif [[ ! "${2:-}" == "-"* ]]
        then
            NEXT_ARG="${2:-}"
            SKIP=2
        else
            NEXT_ARG=""
            SKIP=1
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
        esac

        if ! isin "${THIS_ARG}" ${VALID_SBATCH_FLAGS_OPTIONAL_VALUE[@]} ${VALID_SBATCH_ARGS[@]}
        then
            break
        fi

        SLURM_ARGS=( "${SLURM_ARGS[@]}" "${THIS_ARG}" )

        if ( isin "${THIS_ARG}" "${VALID_SBATCH_ARGS[@]}" ) && [ -z "${NEXT_ARG:-}" ]
        then
            echo_stderr "ERROR: ${THIS_ARG} expects a value."
            exit 1
        elif [ ! -z "${NEXT_ARG:-}" ]
        then
            SLURM_ARGS=( "${SLURM_ARGS[@]}" "${NEXT_ARG:-}" )
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

    # Check if we've got parallel
    if ! which parallel > /dev/null
    then
        echo_stderr "This script requires GNU parallel to be available on your path."
        exit 1
    fi

fi


# Set a couple of default slurm parameters if they werent given

if [ "${SLURM_STDOUT_SET}" = false ] && [ "${SLURM_STDERR_SET}" = false ]
then
    SLURM_ARGS=( "${SLURM_ARGS[@]}" "--output" "${SLURM_STDOUT_DEFAULT}" )
    SLURM_ARGS=( "${SLURM_ARGS[@]}" "--error" "${SLURM_STDERR_DEFAULT}" )
fi

if [ "${SLURM_EXPORT_SET}" = false ]
then
    SLURM_ARGS=( "${SLURM_ARGS[@]}" "--export" "${SLURM_EXPORT_DEFAULT}" )
fi

if [ "${SLURM_ACCOUNT_SET}" = false ]
then
    SLURM_ARGS=( "${SLURM_ARGS[@]}" "--account" "${SLURM_ACCOUNT_DEFAULT}" )
fi

if [ "${SLURM_PARTITION_SET}" = false ]
then
    SLURM_ARGS=( "${SLURM_ARGS[@]}" "--partition" "${SLURM_PARTITION_DEFAULT}" )
fi

# Reads stdin or file into an array of lines.
# Note that cat will remove any trailing newlines
CMDS=$(cat "${INFILE}")

# We want to fail early on empty lines or duplicate commands so that everything runs as expected

# The grep removes any empty lines and lines starting with a # (comments)
CMDS_SPACE=$(echo "${CMDS}" | grep -v '^[[:space:]]*$\|^[[:space:]]*#')

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

NJOBS=$(echo "${CMDS}" | wc -l)

if [ "${NJOBS}" -eq 0 ]
then
    echo_sterr "ERROR: We didnt get any tasks to run!"
    exit 1
fi

if [ "${#MODULES[@]}" -gt 0 ]
then
    MODULE_CMD="module load ${MODULES[@]}"
else
    MODULE_CMD=""
fi

if [ ! -z "${RESUME:-}" ]
then
    RESUME_CP='cp -L '"${RESUME}"' "${LOG_FILE_NAME}"'
    RESUME_ARG='--resume '
else
    RESUME_CP=
    RESUME_ARG=
fi

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login

set -euo pipefail

${MODULE_CMD}

$(declare -f gen_slurm_filename)
LOG_FILE_NAME=\$(gen_slurm_filename '${SLURM_LOG}')

${RESUME_CP}

export OMP_NUM_THREADS="\${SLURM_CPUS_PER_TASK:-1}"

cleanup() {
    EXITCODE="\$?"
    # Put any cleanup in here

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

# In this case we need to tell srun to only run 1 task since multi-tasks handled by parallel.
SRUN="srun --nodes 1 --ntasks 1 -c\${SLURM_CPUS_PER_TASK:-1} --exact --export=all"
PARALLEL="parallel --delay 0.5 -j \${SLURM_NTASKS:-1} --joblog '\${LOG_FILE_NAME}' ${RESUME_ARG}"

\${PARALLEL} "\${SRUN} {}" <<CMD_EOF
${CMDS}
CMD_EOF
EOF

if [ "${DRY_RUN}" = "true" ]
then
    echo "RUNNING WITH BATCH SCRIPT:"
    echo "${BATCH_SCRIPT}"
else
    SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch "${SLURM_ARGS[@]}")
    echo ${SLURM_ID}
fi