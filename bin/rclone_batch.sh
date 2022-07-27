#!/usr/bin/env bash

set -euo pipefail

RCLONE_MODULE="rclone/1.58.1"
SCRIPT="$(readlink -f $0)"
DIRNAME="$(dir ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H%M%S')"

# Set defaults
VERSION="v0.0.1"
GROUP="${PAWSEY_PROJECT:-}"
PARTITION="copy"
SUBCOMMAND=

# This sets -x
DEBUG=false

### GET COMMAND LINE PARAMETERS

echo_stderr() {
    echo $@ 1>&2
}

export -f echo_stderr

usage() {
    echo -e 'USAGE:
'
}

usage_err() {
    usage 1>&2
    echo_stderr -e "
Run `${SCRIPT} --help` for extended usage information."
}


help() {
    echo -e "
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


if [ $# -eq 0 ]
then
    usage
    echo "No arguments provided"
    exit 0
fi


isin() {
    PARAM=$1
    shift
    ANYMATCH=false
    for f in $@
    do
        if [[ "${PARAM}" == "${f}"* ]]; then ANYMATCH=true; fi
    done

    echo "${ANYMATCH}"
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --group)
    check_param "--group" "${2:-}"
    GROUP="$2"
    shift 2 # past argument
    ;;
    --partition)
    check_param "--partition" "${2:-}"
    PARTITION="$2"
    shift 2 # past argument
    ;;
    copy|copyto|untar|tar|gunzip|gzip|sync)
    SUBCOMMAND=$key
    shift
    break
    ;;
    -h|--help)
    usage
    help
    exit 0
    ;;
    --debug)
    DEBUG=true
    shift # past argument
    ;;
    -v|--version)
    echo ${VERSION}
    exit 0
    ;;
    --)
    shift
    break
    ;;
    *)    # unknown option 
    echo_stderr "ERROR: Encountered an unknown parameter '${1:-}'."
    usage_err
    exit 1
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

REMOTES=( $(rclone listremotes) )

RCLONE_ARGS=( )
RCLONE_SRC=
RCLONE_SRC_LOCAL=
RCLONE_DEST=
RCLONE_DEST_LOCAL=
RCLONE_HAS_FILTERS=false
RCLONE_TRANSFERS=12
RCLONE_TRANSFERS_SET=false

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
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
    echo_stderr "Cannot do interactive transfers with batch script."
    exit 1
    shift # past argument
    ;;
    *)    # unknown option 
    if [[ ! "$1" == -* ]]
    then
	if [ $(isin $1 ${REMOTES[@]}) = "true" ]
        then
	    if [ -z "${RCLONE_SRC:-}" ]
            then
                RCLONE_SRC=$1
		RCLONE_SRC_LOCAL=false
	    elif [ -z "${RCLONE_DEST:-}" ]
	    then
	        RCLONE_DEST=$1
		RCLONE_DEST_LOCAL=false
	    else
	        echo_stderr "Rclone copy commands only take two positional argument, unexpected $1"
		exit 1
	    fi
	elif [ -f "$1" ] || [ -d "$1" ]
	then
	    if [ -z "${RCLONE_SRC:-}" ]
	    then
                RCLONE_SRC=$1
		RCLONE_SRC_LOCAL=true
	    elif [ -z "${RCLONE_DEST:-}" ]
	    then
	        RCLONE_DEST=$1
		RCLONE_DEST_LOCAL=true
	    else
	        echo_stderr "Rclone copy commands only take two positional argument, unexpected $1"
		exit 1
	    fi
	else
	    if [ ! -z "${RCLONE_SRC}" ] && [ -z "${RCLONE_DEST}" ]
	    then
		# We can only take non-existent files as destinations
		# because a source should always point to either remote or an existing file.
	        RCLONE_DEST=$1
		RCLONE_DEST_LOCAL=true
	    else
	        echo_stderr "Got a positional argument that doesn't start with a remote path or a local path. Unexpected $1"
            exit 1 
            fi
        fi
    else
        RCLONE_ARGS=( "${RCLONE_ARGS[@]}" "$1")
    fi
    shift
    ;;
esac
done


if [ ${SUBCOMMAND} == "cat" ] && ! ${RCLONE_DEST_LOCAL}
then
    echo_stderr "If you want to use untar or gunzip, the destination file must be local."
    exit 1
elif [ ${SUBCOMMAND} == "cat" ] && ${RCLONE_SRC_LOCAL}
then
    echo_stderr "If you want to use untar or gunzip, the source file must be remote."
    exit 1
elif [ ${SUBCOMMAND} == "rcat" ] && ${RCLONE_DEST_LOCAL}
then
    echo_stderr "If you want to use tar or gzip, the destination file must be remote."
    exit 1
elif [ ${SUBCOMMAND} == "rcat" ] && ! ${RCLONE_SRC_LOCAL}
then
    echo_stderr "If you want to use tar or gzip, the source file must be local."
    exit 1
fi

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
