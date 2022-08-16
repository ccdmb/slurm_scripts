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
SLURM_JOB_NAME_SET=false
SLURM_JOB_NAME_DEFAULT=$(basename "${SCRIPT%%.*}")

PARALLEL_MODULE="${SLURM_SCRIPTS_PARALLEL_MODULE:-}"

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
  --batch-resume -- Resume the jobarray, skipping previously successful jobs according to the file provided here.
  --batch-dry-run -- Print the command that will be run and exit.
  --batch-module -- Include this module the sbatch script. Can be specified multiple times.
  --batch-parallel-module -- Module needed to load GNU parallel. Takes a default argument from environment variable SLURM_SCRIPTS_PARALLEL_MODULE. If that is empty, assumes that parallel is already on your PATH.
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.
  --batch-version -- Print the version and exit.

All other parameters, flags and arguments before '--' are passed to sbatch as is.
See: https://slurm.schedmd.com/sbatch.html

Note: you can't provide the --array flag, as parallelism is handled a different way and it will raise an error.

For more complex scripts, I'd suggest wrapping it in a separate script.
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
        --batch-parallel-module)
            check_param "--batch-parallel-module" "${2:-}"
            PARALLEL_MODULE="$2"
            shift 2 # past argument
            ;;
        -a|--array|-a=*|--array=*)
            echo_stderr "ERROR: This script cannot be used alongside job-array execution."
            echo_stderr "ERROR: Remove the \`--array\` parameter or try the sbatch_jobarray.sh command."
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

### Prepare software

# Attempts to load the module, but it's ok if not
# Module is a bit weird, it doesn't seem to exist on PATH.
# And it returns 1 with help.
# Here we rely on 127 if the command isn't found.
MODULE_RC=0
module > /dev/null 2>&1 || MODULE_RC=$?

# 0 or 1 would be success conditions as --help returns 1
if [ "${MODULE_RC}" -gt 1 ] && (! declare -f module > /dev/null 2>&1)
then
    HAVE_MODULE=false
else
    HAVE_MODULE=true
fi

if [ "${HAVE_MODULE}" = "true" ] && [ ! -z "${PARALLEL_MODULE:-}" ]
then
    module load "${PARALLEL_MODULE}"
    MODULES+=( "${PARALLEL_MODULE}" )
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

# Reads stdin or file into an array of lines.
# Note that cat will remove any trailing newlines
CMDS=$(cat "${INFILE}" | sort)

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

if ! diff <(echo "${CMDS}" | sort) <(echo "${CMDS_UNIQUE}") 1>&2
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
    RESUME_ARG='--resume-failed '
else
    RESUME_CP=
    RESUME_ARG=
fi

SBATCH_DIRECTIVES=$(printf "#SBATCH ")
DIRECTIVES=$(printf "#SBATCH %s\n" "${SLURM_ARGS[@]}")

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login
${DIRECTIVES}

set -euo pipefail

${MODULE_CMD}

LOG_FILE_NAME=\$(${DIRNAME}/gen_slurm_filename.py '${SLURM_LOG}')

${RESUME_CP}

export OMP_NUM_THREADS="\${SLURM_CPUS_PER_TASK:-1}"

cleanup()
{
    EXITCODE="\$?"
    # Put any cleanup in here

    echo -e "\n"
    seff "\${SLURM_JOBID}" | grep -v "WARNING: Efficiency statistics may be misleading for RUNNING jobs." || true
    echo -e "\n"

    if [ "\${EXITCODE}" -ne 0 ]
    then
        # We are putting this to stdout. stderr already has a warning from srun
        # This points to you stderr if its in a separate file
        echo -e "###########  ERROR!!! #############\n"
        echo "ERROR: srun returned a non-zero status: \${EXITCODE}."
        echo "ERROR: Please look at the error and log files to find the problem."
    fi

    return "\${EXITCODE}"
}

trap cleanup EXIT

# In this case we need to tell srun to only run 1 task since multi-tasks handled by parallel.
SRUN="srun --nodes 1 --ntasks 1 --cpus-per-task \${SLURM_CPUS_PER_TASK:-1} --exact --export=all"
PARALLEL="parallel --delay 0.5 -j \${SLURM_NTASKS:-1} --joblog \${LOG_FILE_NAME} ${RESUME_ARG}"

\${PARALLEL} "\${SRUN} bash -c {}" <<'CMD_EOF'
${CMDS}
CMD_EOF
EOF

if [ "${DRY_RUN}" = "true" ]
then
    echo "${BATCH_SCRIPT}"
else
    SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --parsable)
    echo ${SLURM_ID}
fi
