#!/usr/bin/env bash

set -euo pipefail

RCLONE_MODULE="rclone/1.58.1"
SCRIPT="$(readlink -f $0)"
DIRNAME="$(dir ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H%M%S')"

# Set defaults
VERSION="v0.0.1"
GROUP="${PAWSEY_PROJECT:-UNSET}"
PARTITION="copy"
VALID_SUBCOMMANDS=( copy copyto untar tar gunzip gzip sync )
SUBCOMMAND=

RCLONE_SRC=
RCLONE_SRC_LOCAL=
RCLONE_DEST=
RCLONE_DEST_LOCAL=
RCLONE_HAS_FILTERS=false
RCLONE_TRANSFERS=12
RCLONE_TRANSFERS_SET=false


# This sets -x
DEBUG=false

### GET COMMAND LINE PARAMETERS

echo_stderr() {
    echo $@ 1>&2
}

export -f echo_stderr

function join_by { local IFS="$1"; shift; echo "$*"; }
export -f join_by

usage() {
    echo -e "USAGE:
${SCRIPT} [$(join_by , ${VALID_SUBCOMMANDS[@]})] SRC DEST [arguments]
"
}

usage_err() {
    usage 1>&2
    echo_stderr -e "
Run \`${SCRIPT} --batch-help\` for extended usage information."
}


help() {
    echo -e "
This script is a wrapper around Rclone, which automatically submits a SLURM job to the queue.
It requires Rclone and Slurm installed in your environment.

Positional arguments:
  $(join_by , ${VALID_SUBCOMMANDS[@]}) -- The subcommand to run.
    tar and gzip based options are new to this, and work by streaming data from or
    to the remote while compressing or decompressing results.
    Decompression only works going from remote to local, compression only works the other way.

  SRC -- The source file or directory to copy. Structure is the same as rclone
  DEST -- The destination file or directory to copy. Structure is the same as rclone

Parameters:
  --batch-group GROUP -- Which account should the slurm job be submitted under. DEFAULT: ${GROUP}
  --batch-partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: ${PARTITION}
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.

All other parameters, flags and arguments are passed to rclone as is.
If --transfers is unset, we set it to 12 (from the default of 4) which is the Pawsey recommendation.

NB. using --interactive will raise an error because interactive jobs wouldn't work in a batch job.
NB. Using --filter, --include, or --exclude will raise an error for tar or gzip subcommands.
    This may change in the future.
"
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


isin() {
    PARAM=$1
    shift
    for f in $@
    do
        if [[ "${PARAM}" == "${f}"* ]]; then return 0; fi
    done

    return 1
}

isremote() {
    REMOTES=( $(rclone listremotes) )
    return isin $1 ${REMOTES[@]}
}

islocal() {
    return [ -f "$1" ] || [ -d "$1" ]
}

if [ $# -eq 0 ]
then
    echo "No arguments provided"
    usage
    help
    exit 0
fi


### Prepare software

# Attempts to load the module, but it's ok if not
if which module > /dev/null
then
    module load "${RCLONE_MODULE}" | true
fi

if ! which rclone > /dev/null
then
    echo_stderr "This script requires rclone to be available, either already on your path or via the module '${RCLONE_MODULE}'."
    exit 1
fi

# Check if we've got sbatch
if ! which sbatch > /dev/null
then
    echo_stderr "This script requires sbatch to be available on your path."
    exit 1
fi


### Process the arguments

# We'll store the args to be passed to rclone in here
RCLONE_ARGS=( )

# The subcommand should always be first
SUBCOMMAND=$1
shift

if [ $(isin "${SUBCOMMAND}" ${VALID_SUBCOMMANDS[@]}) = "false" ]
then
    echo_stderr "ERROR: Got unexpected subcommand '${SUBCOMMAND}'"
    echo_stderr "ERROR: The first argument must be one of ${VALID_SUBCOMMANDS[@]}"
    usage_err
    exit 1
fi

# We're enforcing that the SRC and DEST must always be first
# This just makes it easier to parse and is inline with the Rclone docs anyway

RCLONE_SRC=$1

if (! isremote "${RCLONE_SRC}") && (! islocal "${RCLONE_SRC}" )
then
    echo_stderr "ERROR: The source file must either be remote or it must exist on the local filesystem."
    usage_err
    exit 1
fi
shift

RCLONE_DEST=$1
if [[ "${RCLONE_DEST}" == "-"* ]]
then
    echo_stderr "WARNING: Your destination file \`${RCLONE_DEST}\` looks like it might be an argument."
    echo_stderr "WARNING: Please double check that this is desired."
fi
shift


# For the streaming options, we need to check that the source is in the
# right location
if ( isin "${SUBCOMMAND}" tar gzip ) && ( isremote "${RCLONE_SRC}" )
then
    echo_stderr "ERROR: When using tar or gzip subcommands, the source must be on the local filesystem."
    usage_err
    exit 1
elif ( isin "${SUBCOMMAND}" tar gzip ) && ( islocal "${RCLONE_DEST}" )
then
    echo_stderr "ERROR: When using tar or gzip subcommands, the destination must be on the remote filesystem."
    usage_err
    exit 1
fi

if ( isin "${SUBCOMMAND}" untar gunzip ) && ( islocal "${RCLONE_SRC}" )
then
    echo_stderr "ERROR: When using untar or gunzip subcommands, the source must be on the remote filesystem."
    usage_err
    exit 1
elif ( isin "${SUBCOMMAND}" untar gunzip ) && ( isremote "${RCLONE_DEST}" )
then
    echo_stderr "ERROR: When using untar or gunzip subcommands, the destination must be on the local filesystem."
    usage_err
    exit 1
fi


# Here we catch our special parameters and collect the rclone ones
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --batch-group)
            check_param "--batch-group" "${2:-}"
            GROUP="$2"
            shift 2 # past argument
            ;;
        --batch-partition)
            check_param "--batch-partition" "${2:-}"
            PARTITION="$2"
            shift 2 # past argument
            ;;
        --batch-help)
            usage
            help
            exit 0
            ;;
        --batch-debug)
            DEBUG=true
            shift # past argument
            ;;
        --batch-version)
            echo ${VERSION}
            exit 0
            ;;
        --filter|--include|--exclude)
            RCLONE_HAS_FILTERS=true
            RCLONE_ARGS=( "${RCLONE_ARGS[@]}" "$1", "$2")
            shift 2 # past argument
            ;;
        --transfers)
            RCLONE_TRANSFERS_SET=true
            RCLONE_ARGS=( "${RCLONE_ARGS[@]}" "$1", "$2")
            shift 2 # past argument
            ;;
        --interactive)
            echo_stderr "ERROR: Cannot do interactive transfers with batch script."
            echo_stderr "ERROR: Remove the \`--interactive\` flag."
            exit 1
            shift # past argument
            ;;
        --help)
            echo "WARNING: ,For more detailed help, please call rclone directly."

            rclone --help
            exit 0
            ;;
        --version)
            rclone --version
            exit 0
            ;;
        *)    # unknown option, passed to rclone
            RCLONE_ARGS=( "${RCLONE_ARGS[@]}" "$1")
            shift
            ;;
    esac
done

if [ "${DEBUG:-}" = "true" ]
then
    set -x
fi

### CHECK USER ARGUMENTS

FAILED=false
[ -z "${GROUP:-}" ] && echo_stderr "Please provide a group account to use for the slurm queue." && FAILED=true
[ -z "${PARTITION:-}" ] && echo_stderr "Please provide a partition/queue to use." && FAILED=true
[ -z "${SUBCOMMAND:-}" ] && echo_stderr "This script can only be used with the copy, copyto, and sync rclone commands." && FAILED=true

if [ "${FAILED}" = true ]
then
    echo_stderr
    usage_err
    exit 1;
fi


### CHECK OTHER ARGS

while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
    esac
done


if ! ${RCLONE_TRANSFERS_SET}
then
    RCLONE_ARGS=( "${RCLONE_ARGS[@]}" "--transfers" "${RCLONE_TRANSFERS}" )
fi

read -r -d '' RUN_BATCH <<EOF || true
#!/bin/bash --login
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --account="${GROUP}"
#SBATCH --partition="${PARTITION}"
#SBATCH --job-name="rclone_${SUBCOMMAND}_${TIME}"
#SBATCH --export=NONE

module load ${RCLONE_MODULE}

srun rclone ${SUBCOMMAND} "${RCLONE_SRC}" "${RCLONE_DEST}" ${RCLONE_ARGS[@]} 
EOF

read -r -d '' UNTAR_BATCH <<EOF || true
#!/bin/bash --login
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --account="${GROUP}"
#SBATCH --partition="${PARTITION}"
#SBATCH --job-name="rclone_${SUBCOMMAND}_${TIME}"
#SBATCH --export=NONE

module load ${RCLONE_MODULE}

mkdir -p "${RCLONE_DEST}"
rclone cat "${RCLONE_SRC}" ${RCLONE_ARGS[@]} \
| tar xf - --directory "${RCLONE_DEST}" --use-compress-program="pigz"
EOF

read -r -d '' TAR_BATCH <<EOF || true
#!/bin/bash --login
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --account="${GROUP}"
#SBATCH --partition="${PARTITION}"
#SBATCH --job-name="rclone_${SUBCOMMAND}_${TIME}"
#SBATCH --export=NONE

module load ${RCLONE_MODULE}

cd "${RCLONE_SRC}"
tar cf - . --use-compress-program="pigz" \
| rclone rcat "${RCLONE_DEST}" ${RCLONE_ARGS[@]}
EOF

read -r -d '' GUNZIP_BATCH <<EOF || true
#!/bin/bash --login
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --account="${GROUP}"
#SBATCH --partition="${PARTITION}"
#SBATCH --job-name="rclone_${SUBCOMMAND}_${TIME}"
#SBATCH --export=NONE

module load ${RCLONE_MODULE}

rclone cat "${RCLONE_SRC}" ${RCLONE_ARGS[@]} \
| pigz -d - \
> "${RCLONE_DEST}"
EOF

read -r -d '' GZIP_BATCH <<EOF || true
#!/bin/bash --login
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --account="${GROUP}"
#SBATCH --partition="${PARTITION}"
#SBATCH --job-name="rclone_${SUBCOMMAND}_${TIME}"
#SBATCH --export=NONE

module load ${RCLONE_MODULE}

pigz -6 --to-stdout --rsyncable "${RCLONE_SRC}" \
| rclone rcat ${RCLONE_DEST} ${RCLONE_ARGS[@]}
EOF


case ${SUBCOMMAND} in
    copy|copyto|sync)
        BATCH="${RUN_BATCH}"
        ;;
    tar)
        BATCH="${TAR_BATCH}"
        ;;
    untar)
        BATCH="${UNTAR_BATCH}"
        ;;
    gzip)
        BATCH="${GZIP_BATCH}"
        ;;
    gunzip)
        BATCH="${GUNZIP_BATCH}"
        ;;
    *)
        echo_stderr "ERROR: this point shouldn't be reachable"
        exit 1
esac

SLURM_ID=$(echo "${BATCH}" | sbatch --parsable)

echo "${SLURM_ID}"
