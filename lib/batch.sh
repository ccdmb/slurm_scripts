#!/usr/bin/env bash

set -euo pipefail

VALID_SBATCH_FLAGS=( --contiguous -h --help -H --hold --ignore-pbs -O --overcommit -s --oversubscribe --parsable --spread-job -Q --quiet --reboot --requeue -Q --quiet --reboot --requeue --test-only --usage --use-min-nodes -v --verbose -W --wait -V --version )
VALID_SBATCH_FLAGS_OPTIONAL_VALUE=( --exclusive --get-user-env --nice -k --no-kill --propagate )
VALID_SBATCH_ARGS=( -a --array -A --account --bb --bbf -b --begin --comment --cpu-freq -c --cpus-per-task -d --dependency --deadline --delay-boot -D --chdir -e --error --export --export-file --get-user-env --gid --gres --gres-flags -i --input -J --job-name -L --licenses -M --clusters --container -m --distribution --mail-type --mail-user --mcs-label -n --ntasks --no-requeue --ntasks-per-node -N --nodes -o --output -p --partition --power --priority --profile -q --qos -S --core-spec --signal --switches --thread-spec -t --time --time-min --uid --wckey --wrap --cluster-constraint -C --constraint -F --nodefile --mem --mincpus --reservation --tmp -w --nodelist -x --exclude --mem-per-cpu --sockets-per-node --cores-per-socket --threads-per-core -B --extra-node-info --ntasks-per-core --ntasks-per-socket --hint --mem-bind --cpus-per-gpu -G --gpus --gpu-bind --gpu-freq --gpus-per-node --gpus-per-socket --gpus-per-task --mem-per-gpu )


delayed() {
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
    OLD_JOBID="${1}"
    NEW_JOBID="${2}"

    TO_UPDATE=$(
        squeue --states="PENDING,REQUEUE_FED,REQUEUE_HOLD,REQUEUED" --format "%i %E" \
        | awk -v JID="${OLD_JOBID}" '$1 == JID {print $2}'
    )
}
