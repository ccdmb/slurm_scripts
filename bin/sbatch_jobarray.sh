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
SLURM_STDOUT_DEFAULT="%x-%A_%4a.stdout"
SLURM_STDERR_SET=false
SLURM_STDERR_DEFAULT="%x-%A_%4a.stderr"
SLURM_LOG="%x-%A_%4a.log"
SLURM_EXPORT_SET=false
SLURM_EXPORT_DEFAULT=NONE
SLURM_ACCOUNT_SET=false
SLURM_ACCOUNT_DEFAULT="${PAWSEY_PROJECT:-UNSET}"
SLURM_PARTITION_SET=false
SLURM_PARTITION_DEFAULT="work"

# This sets -x
DEBUG=false

source "${DIRNAME}/../lib/bash_utils/general.sh" @
source "${DIRNAME}/../lib/bash_utils/cli.sh" @
source "${DIRNAME}/../lib/batch.sh" @

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
  --batch-pack -- Pack the job
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
        --batch-log)
            check_param "--batch-log" "${2:-}"
            SLURM_LOG="${2}"
            shift 2
            ;;
        --batch-resume)
            check_no_default_param "--batch-module" "${RESUME:-}" "${2:-}"
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

if [ ! -z "${RESUME:-}" ]
then
    RESUME_CLEANED=$(cat "${RESUME}" | grep -v "^[[:space:]]*$\|^[[:space:]]*#" | sort -u)
    MIN_NCOLS=$(echo "${RESUME_CLEANED}" | awk -F'\t' 'BEGIN {MINNF=0} {if (NR == 1) {MINNF = NF}; if ( NF > 0 ) {MINNF=(MINNF < NF ? MINNF : NF)} } END {print MINNF}')
    RESUME="${RESUME_CLEANED}"
    unset RESUME_CLEANED

    if [ "${MIN_NCOLS}" -lt 3 ]
    then
        echo_stderr "ERROR: At least one entry in the file provided to --batch-resume contained ${MIN_NCOLS} columns."
        echo_stderr "ERROR: We need at least 3 columns to figure out what to do."
        exit 1
    elif [ "${MIN_NCOLS}" -eq 3 ]
    then
        readarray -t COMPLETED_INDICES < <(echo "${RESUME}" | awk -F '\t' '$3 == 0 {print $2}' | sort)
        readarray -t CMDS < <(echo "${CMDS}")

        COMPLETED_CMDS=( )
        for i in "${COMPLETED_INDICES[@]}"
        do
            if [ ${i} -lt ${NJOBS} ]
            then
                COMPLETED_CMDS+=( "${CMDS[${i}]}" )
                unset CMDS[${i}]
            fi
        done

        # This is so the indices are normal again
        if [ "${#CMDS[@]}" -gt 0 ]
        then
            CMDS=( "${CMDS[@]}" )
        fi


        echo_stderr '######################################'
        echo_stderr "Skipping the following commands because they were in the file provided to --batch-resume"
        for line in "${COMPLETED_CMDS[@]}"
        do
            echo_stderr "COMPLETED: ${COMPLETED_CMDS}"
        done

    else
        COMPLETED_CMDS="$(echo -e "${RESUME}" | awk -F '\t' '$3 == 0' | cut -d'	' -f4-)"

        # This prints anything in CMDs that isn't in COMPLETED_CMDS
        REMAINING_CMDS=$(grep -f <(echo "${COMPLETED_CMDS}") -F -v <(echo "${CMDS}") || : )

        if [ -z "$( echo '${REMAINING_CMDS}' | sed 's/[[:space:]]//g')" ]
        then
            CMDS=( )
        else
            readarray -t CMDS < <(echo "${REMAINING_CMDS}")
        fi
        unset REMAINING_CMDS

        COMPLETED_CMDS=$(echo "${COMPLETED_CMDS}" | awk '{print "COMPLETED: " $0}')
        echo_stderr '######################################'
        echo_stderr "Skipping the following commands because they were in the file provided to --batch-resume"
        # echo stderr doesn't preserve newlines
        echo "${COMPLETED_CMDS}" 1>&2
        unset COMPLETED_CMDS
    fi
else
    readarray -t CMDS < <(echo "${CMDS}")
fi

NJOBS="${#CMDS[@]}"

if [ "${NJOBS}" -eq 0 ]
then
    echo_stderr "After filtering completed jobs there were no jobs left..."
    echo_stderr "Not submitting SLURM job"
    exit 0
fi

echo "${CMDS[@]}"
exit 0

if [ "${#MODULES[@]}" -gt 0 ]
then
    MODULE_CMD="module load ${MODULES[@]}"
else
    MODULE_CMD=""
fi

read -r -d '' BATCH_SCRIPT <<EOF || true
#!/bin/bash --login

set -euo pipefail

${MODULE_CMD}

JOBID="\${SLURM_ARRAY_JOB_ID}_\${SLURM_ARRAY_TASK_ID}"

$(declare -f gen_slurm_filename)
LOG_FILE_NAME=\$(gen_slurm_filename '${SLURM_LOG}')

cleanup() {
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

read -r -d '' SRUN_SCRIPT <<'EOF_SRUN'  || true
#!/usr/bin/env bash

set -euo pipefail

$(declare -a -p CMDS)

INDEX="\$(( \${SLURM_ARRAY_TASK_ID:-0} + \${SLURM_PROCID:-0} ))"

if [ "\${INDEX}" -gt $(( ${NJOBS} - 1 )) ]
then
    exit 0
fi

# Yeah i know we are redefining this, but i dont want
# to remove the quotes from the eof because then id have to
# escape more.
$(declare -f gen_slurm_filename)
LOG_FILE_NAME=\$(gen_slurm_filename '${SLURM_LOG}')

$(declare -f write_log)

actually_write_log() {
    EXITCODE="\$?"
    write_log "\${LOG_FILE_NAME}" "\${SLURM_JOB_NAME:-\(none\)}" "\${INDEX:-0}" "\${EXITCODE}" "\${CMDS[\${INDEX}]}"
}

trap actually_write_log EXIT

eval "\${CMDS[\${INDEX}]}"
EOF_SRUN

echo "\${SRUN_SCRIPT}" \
| srun --nodes "\${SLURM_JOB_NUM_NODES:-1}" \
  --ntasks "\${SLURM_NTASKS:-1}" \
  --cpus-per-task "\${SLURM_CPUS_PER_TASK:-1}" \
  --export=all \
  bash
EOF

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

if [ "${DRY_RUN}" = "true" ]
then
    echo "RUNNING AS:"
    echo "sbatch --array='${ARRAY_STR}' ""${SLURM_ARGS[@]}"
    echo "WITH BATCH SCRIPT:"
    echo "${BATCH_SCRIPT}"
else
    SLURM_ID=$(echo "${BATCH_SCRIPT}" | sbatch --array="${ARRAY_STR}" "${SLURM_ARGS[@]}")
    echo ${SLURM_ID}
fi
