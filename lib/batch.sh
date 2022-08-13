#!/usr/bin/env bash

set -euo pipefail

__SBATCH_DIRNAME=$(dirname "${BASH_SOURCE[0]}")
__SBATCH_ALL=(
    write_log gen_slurm_filename lift_fn update_dependencies
    VALID_SBATCH_FLAGS VALID_SBATCH_FLAGS_OPTIONAL_VALUE VALID_SBATCH_ARGS
)

source "${__SBATCH_DIRNAME}/bash_utils/import.sh" save "${BASH_SOURCE[0]}" "${__SBATCH_ALL[@]:-}"
source "${__SBATCH_DIRNAME}/bash_utils/general.sh" echo_stderr


VALID_SBATCH_FLAGS=(
    --contiguous -h --help -H --hold --ignore-pbs -O --overcommit
    -s --oversubscribe --parsable --spread-job -Q --quiet --reboot
    --requeue -Q --quiet --reboot --requeue --test-only --usage
    --use-min-nodes -v --verbose -W --wait -V --version
)

VALID_SBATCH_FLAGS_OPTIONAL_VALUE=(
    --exclusive --get-user-env --nice -k
    --no-kill --propagate
)

VALID_SBATCH_ARGS=(
    -a --array -A --account --bb --bbf -b --begin --comment
    --cpu-freq -c --cpus-per-task -d --dependency --deadline
    --delay-boot -D --chdir -e --error --export --export-file
    --get-user-env --gid --gres --gres-flags -i --input -J --job-name
    -L --licenses -M --clusters --container -m --distribution
    --mail-type --mail-user --mcs-label -n --ntasks --no-requeue
    --ntasks-per-node -N --nodes -o --output -p --partition
    --power --priority --profile -q --qos -S --core-spec --signal
    --switches --thread-spec -t --time --time-min --uid --wckey
    --wrap --cluster-constraint -C --constraint -F --nodefile --mem
    --mincpus --reservation --tmp -w --nodelist -x --exclude
    --mem-per-cpu --sockets-per-node --cores-per-socket
    --threads-per-core -B --extra-node-info --ntasks-per-core
    --ntasks-per-socket --hint --mem-bind --cpus-per-gpu -G --gpus
    --gpu-bind --gpu-freq --gpus-per-node --gpus-per-socket
    --gpus-per-task --mem-per-gpu
)

gen_slurm_filename() {
    TEMPLATE="$1"

    echo "${1}" \
    | python3 -c "
import re
import sys


def pad(val):
    def inner(match):
        if match.group('pad') is None:
            pad = 1
        else:
            pad = int(match.group('pad'))
        val_ = int(val)
        return f'{val_:0>{pad}}'
    return inner


sub = sys.stdin.read().strip()

if re.search(r'\\\\', sub) is not None:
    print(sub)
    sys.exit(0)

sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?A', pad(${SLURM_ARRAY_JOB_ID:-1}), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?a', pad(${SLURM_ARRAY_TASK_ID:-2}), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?J', '${SLURM_JOB_ID:-ERR}.${SLURM_LOCALID:-ERR}', sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?j', pad(${SLURM_JOB_ID:-3}), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?N', '${SLURMD_NODENAME:-ERR}', sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?n', pad(${SLURM_NODEID:-4}), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?s', pad(${SLURM_LOCALID:-5}), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?t', pad(${SLURM_LOCALID:-6}), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?u', '${USER:-ERR}', sub)
sub = re.sub(r'(?<!%)%(?P<pad>\\d+)?x', '${SLURM_JOB_NAME:-7}', sub)
sub = re.sub(r'%%', r'%', sub)
print(sub)
"
}


write_log() {
    LOGFILE="${1}"
    JOBNAME="${2}"
    INDEX="${3}"
    EXITCODE="${4}"
    CMD="${5:-}"

    exec 100> "${LOGFILE}.lock"
    # Obtain a lock on logfile
    # This avoids multiple processes writing to the same file at once.
    # timeout if waiting for more than an hour
    flock -x --wait 3600 100

    if [ -z "${CMD:-}" ]
    then
        CMD_PRINT=""
    else
        CMD_PRINT="	${CMD}"
    fi

    echo "${JOBNAME}	${INDEX}	${EXITCODE}${CMD_PRINT}" >> "${LOGFILE}"
    # Hold the lock for 10 seconds just in case the different tasks are accessing
    # different shards in the NFS. Sometimes files can take a while to become visible.
    sleep 10
    return "${EXITCODE}"
}


lift_fn() {
    DEP="${1}"
    FUNC=$(declare -f "${2}")
    FUNC_NAME="${2}"

    read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login

set -euo pipefail

${FUNC}

${FUNC_NAME}

EOF
    SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --dependency="${DEP}")
    echo "${SLURM_ID}"
}


update_dependencies() {
    # Updates any dependencies of OLD_JOBID to instead depend on NEW_JOBID
    OLD_JOBID="${1}"
    NEW_JOBID="${2}"

    readarray -t SQUEUE < <(
    squeue --states="PENDING,REQUEUE_FED,REQUEUE_HOLD,REQUEUED" --format "%i %E" \
    | tail -n+2 \
    | awk -v oldjobid="${OLD_JOBID}" -v newjobid="${NEW_JOBID}" '
        BEGIN {OFS="\t"}
        $2 != "(null)" && $2 ~ oldjobid {
            s=gensub(/\([^\)]*\)/, "", "g", $2);
            sub(oldjobid, newjobid, s);
            print $1, s
        }
    '
    )

    for i in "${!SQUEUE[@]}"
    do
        # Make sure the cut -d in 2 is a tab
        JOBID=$(echo "${SQUEUE[${i}]}" | cut -d'	' -f1)
        DEPS=$(echo "${SQUEUE[${i}]}" | cut -d'	' -f2-)
        scontrol update job "${JOBID}" Dependency="${DEPS}"
    done
}


source "${__SBATCH_DIRNAME}/bash_utils/import.sh" restore "${BASH_SOURCE[0]}" "${@:-}" -- "${__SBATCH_ALL[@]:-}"

unset __SBATCH_DIRNAME
unset __SBATCH_ALL
