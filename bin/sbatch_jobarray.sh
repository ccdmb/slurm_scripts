#!/usr/bin/env bash

set -euo pipefail

SCRIPT="$(readlink -f $0)"
DIRNAME="$(dirname ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H%M%S')"

# Set defaults
VERSION="v0.0.1"
DRY_RUN=false
PACK=false
MODULES=( )
GROUP=

NTASKS_PER_NODE=
NODES=
NTASKS=
CPUS_PER_TASK=

NPARAMS=1

SLURM_STDOUT_SET=false
SLURM_STDOUT_DEFAULT="${TIME}-%A-%a.stdout"
SLURM_STDERR_SET=false
SLURM_STDERR_DEFAULT="${TIME}-%A-%a.stderr"
SLURM_EXPORT_SET=false
SLURM_EXPORT_DEFAULT=NONE
SLURM_ACCOUNT_SET=false
SLURM_ACCOUNT_DEFAULT="${PAWSEY_PROJECT:-UNSET}"
SLURM_PARTITION_SET=false
SLURM_PARTITION_DEFAULT="work"

VALID_SLURM_FLAGS=( --contiguous -h --help -H --hold --ignore-pbs -O --overcommit -s --oversubscribe --parsable --spread-job -Q --quiet --reboot --requeue -Q --quiet --reboot --requeue --test-only --usage --use-min-nodes -v --verbose -W --wait -V --version )
VALID_SLURM_FLAGS_OPTIONAL_VALUE=( --exclusive --get-user-env --nice -k --no-kill --propagate )
VALID_SLURM_ARGS=( -a --array -A --account --bb --bbf -b --begin --comment --cpu-freq -c --cpus-per-task -d --dependency --deadline --delay-boot -D --chdir -e --error --export --export-file --get-user-env --gid --gres --gres-flags -i --input -J --job-name -L --licenses -M --clusters --container -m --distribution --mail-type --mail-user --mcs-label -n --ntasks --no-requeue --ntasks-per-node -N --nodes -o --output -p --partition --power --priority --profile -q --qos -S --core-spec --signal --switches --thread-spec -t --time --time-min --uid --wckey --wrap --cluster-constraint -C --constraint -F --nodefile --mem --mincpus --reservation --tmp -w --nodelist -x --exclude --mem-per-cpu --sockets-per-node --cores-per-socket --threads-per-core -B --extra-node-info --ntasks-per-core --ntasks-per-socket --hint --mem-bind --cpus-per-gpu -G --gpus --gpu-bind --gpu-freq --gpus-per-node --gpus-per-socket --gpus-per-task --mem-per-gpu )

# This sets -x
DEBUG=false

source "${DIRNAME}/../lib/cli.sh"

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
  --output -- The output filename of the job stdout. default "${TIME}-%A-%a.stdout"
  --error -- The output filename of the job stderr. default "${TIME}-%A-%a.stderr"
  --batch-pack -- Pack the job
  --batch-nparams -- How many parameters to take for each separate job. Default: 1
  --batch-dry-run -- Print the command that will be run and exit.
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.

All other parameters, flags and arguments before '--' are passed to sbatch as is.
See: https://slurm.schedmd.com/sbatch.html

Note: you can't provide the --array flag, as this is set internally and it will raise an error.

After '--':





The first argument is the command that should be run.
If there is space in the command, it must be enclosed in quotes to be interpreted as a single argument.

The second argument is a glob or list of files to be used as input for the job array.
This script will use this glob to determine the size of the job array to run.

By default, each file will be provided to the script as a single argument, but this can be customised using replacement strings.

E.g using a single argument

\`\`\`
./jobarray_glob.sh -- my_script.sh one.fasta two.fasta three.fasta
# Runs this
# my_script.sh one.fasta
# my_script.sh two.fasta
# my_script.sh three.fasta
\`\`\`

If you provide the parameter --batch-nparams this is used to determined how many parameters to pass to the command.
This is designed to work best with the curly brace expansion. E.g.

\`\`\`
./jobarray_glob.sh --batch-nparams 2 -- my_script.sh *-{R1,R2}.fastq.gz
# Runs this
# my_script.sh one-R1.fastq.gz one-R2.fastq.gz
# my_script.sh two-R1.fastq.gz two-R2.fastq.gz

# Explicitly this is the same as
./jobarray_glob.sh --batch-nparams 2 -- my_script.sh one-R1.fastq.gz two-R1.fastq.gz one-R2.fastq.gz two-R2.fastq.gz
\`\`\`

To customise the input provided you can use a subset of the replacement strings defined for gnu parallel.
https://www.gnu.org/software/parallel/parallel_tutorial.html#replacement-strings

Accessing multiple filenames.

\`\`\`
./jobarray_glob.sh --batch-nparams 2 -- "my_script.sh {2} {1}" *-{R1,R2}.fastq.gz
# Would run
# my_script.sh one-R2.fastq.gz one-R1.fastq.gz
# my_script.sh two-R2.fastq.gz two-R1.fastq.gz
\`\`\`


\`\`\`
# Removing dirnames
./jobarray_glob.sh --batch-nparams 1 -- "my_script.sh --out {/} --in {}" mydir/*.fasta
# Would run
# my_script.sh --out one.fasta --in mydir/one.fasta
# my_script.sh --out two.fasta --in mydir/two.fasta

# Removing extensions each additional dot removes another level of extensions
./jobarray_glob.sh --batch-nparams 1 -- "my_script.sh --out {.} --in {}" mydir/*.fasta.gz
# Would run
# my_script.sh --out mydir/one.fasta --in mydir/one.fasta.gz
# my_script.sh --out mydir/two.fasta --in mydir/two.fasta.gz

./jobarray_glob.sh --batch-nparams 1 -- "my_script.sh --out {..} --in {}" mydir/*.fasta.gz
# Would run
# my_script.sh --out mydir/one --in mydir/one.fasta.gz
# my_script.sh --out mydir/two --in mydir/two.fasta.gz

# Removing extension and dirname
./jobarray_glob.sh --batch-nparams 1 -- "my_script.sh --out {/.} --in {}" mydir/*.fasta
# Would run
# my_script.sh --out one --in mydir/one.fasta
# my_script.sh --out two --in mydir/two.fasta

# Getting just the dirname
./jobarray_glob.sh --batch-nparams 1 -- "my_script.sh --out {//} --in {}" mydir/*.fasta
# Would run
# my_script.sh --out mydir/ --in mydir/one.fasta
# my_script.sh --out mydir/ --in mydir/two.fasta

# Using multiple parameters with replacements
./jobarray_glob.sh --batch-nparams 2 -- "my_script.sh --out {1/..} --in1 {1} --in2 {2}" mydir/*.fastq.gz
# Would run
# my_script.sh --out one --in1 mydir/one.fastq.gz --in2 mydir/one.fastq.gz
# my_script.sh --out two --in1 mydir/two.fastq.gz --in2 mydir/two.fastq.gz
\`\`\`

For more complex scripts, I'd suggest wrapping it in a separate script.
Note that unlike GNU parallel and srun, we don't support running functions.
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
        --batch-group)
            check_param "--batch-group" "${2:-}"
            GROUP="$2"
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
        --batch-nparams)
            check_param "--batch-nparam" "${2:-}"
            NPARAMS="$2"
            shift 2
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
        if isin "$1" "${VALID_SLURM_FLAGS[@]}"
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

        if ! isin "${THIS_ARG}" ${VALID_SLURM_FLAGS_OPTIONAL_VALUE[@]} ${VALID_SLURM_ARGS[@]}
        then
            echo_stderr "WARNING: We encountered an unexpected argument (${THIS_ARG}) before --."
            echo_stderr "WARNING: We'll continue as if you had used -- (it's best to explicitly provide it)."
            echo_stderr "WARNING: No further parameters will be passed to SLURM."
            break
        fi

        SLURM_ARGS=( "${SLURM_ARGS[@]}" "${THIS_ARG}" )

        if ( isin "${THIS_ARG}" "${VALID_SLURM_ARGS[@]}" ) && [ -z "${NEXT_ARG:-}" ]
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


if [ "${#@}" = 0 ]
then
    echo_stderr "ERROR: You have not provided a script to run."
    usage_err
    exit 1
fi


SCRIPT=$1
shift
POSITIONAL=( "$@" )

if [ "${#POSITIONAL[@]}" = 0 ]
then
    echo_stderr "ERROR: You have not provided any files to operate on."
    usage_err
    exit 1
elif [ $(( "${#POSITIONAL[@]}" % "${NPARAMS:-1}" )) != 0 ]
then
    echo_stderr "ERROR: The number of inputs specified by your glob (${#POSITIONAL[@]}) is not a multiple of your nparams (${NPARAMS:-1})"
    usage_err
    exit 1
fi

if [ -z "${GROUP:-}" ]
then
    GROUP_ARG=""
else
    GROUP_ARG=" --group '${GROUP}' "
fi

CMDS=$( "${DIRNAME}"/expansion.py ${GROUP_ARG} --nparams "${NPARAMS}" "${SCRIPT}" "${POSITIONAL[@]}" )
NJOBS=$(echo "${CMDS}" | wc -l)

SRUN_SCRIPT="${TMPDIR:-.}/.tmp_${TIME}_$$"
cat <<EOF > "${SRUN_SCRIPT}" || true
#!/usr/bin/env bash

readarray -t CMDS <<EOF_CMDS || true
${CMDS[@]}
EOF_CMDS
export CMDS

export INDEX="\$(( \${SLURM_ARRAY_TASK_ID:-0} + \${SLURM_PROCID:-0} ))"

if [ "\${INDEX}" -gt $(( ${NJOBS} - 1 )) ]
then
    exit 0
fi

eval "\${CMDS[\${INDEX}]}"
EOF

trap "rm -f -- ${SRUN_SCRIPT}" ERR
chmod a+x "${SRUN_SCRIPT}"

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login

set -euo pipefail

module load ${MODULES[@]}

trap "rm -f -- ${SRUN_SCRIPT}" EXIT

srun --nodes "\${SLURM_JOB_NUM_NODES:-1}" \
  --ntasks "\${SLURM_NTASKS:-1}" \
  --cpus-per-task "\${SLURM_CPUS_PER_TASK:-1}" \
  --export=all \
  ${SRUN_SCRIPT}

JOBID="\${SLURM_ARRAY_JOB_ID}_\${SLURM_ARRAY_TASK_ID}"
seff "\${JOBID}" || true
EOF

if [ "${PACK}" = true ]
then
    if [ -z "${NTASKS:-}" ]
    then
        echo_stderr "we shouldnt be able to reach this point."
        exit 1
    fi
    ARRAY_STR="0-$(( ${NJOBS} - 1 )):${NTASKS}"
else
    ARRAY_STR="0-$(( ${NJOBS} - 1 ))"
fi

if [ "${DRY_RUN}" = "true" ]
then
    echo "${BATCH_SCRIPT:-}"
    cat "${SRUN_SCRIPT}"
    echo "BATCH:" sbatch --array="${ARRAY_STR}" "${SLURM_ARGS[@]}"
else
    SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --array="${ARRAY_STR}" "${SLURM_ARGS[@]}")
    echo ${SLURM_ID}
fi
