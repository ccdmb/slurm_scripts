#!/usr/bin/env bash

set -euo pipefail

SCRIPT="$(readlink -f $0)"
DIRNAME="$(dir ${SCRIPT})"
SCRIPT="$(basename ${SCRIPT})"
TIME="$(date +'%Y%m%d-%H%M%S')"

# Set defaults
VERSION="v0.0.1"
GROUP="${PAWSEY_PROJECT:-UNSET}"
PARTITION="work"
NODES=1
NTASKS=
NCPUPERTASK=

NPARAMS=1

VALID_SLURM_FLAGS=( --contiguous -h --help -H --hold --ignore-pbs -O --overcommit -s --oversubscribe --parsable --spread-job -Q --quiet --reboot --requeue -Q --quiet --reboot --requeue --test-only --usage --use-min-nodes -v --verbose -W --wait -V --version )
VALID_SLURM_FLAGS_OPTIONAL_VALUE=( --exclusive --get-user-env --nice -k --no-kill --propagate )
VALID_SLURM_ARGS=( -a --array -A --account --bb --bbf -b --begin --comment --cpu-freq -c --cpus-per-task -d --dependency --deadline --delay-boot -D --chdir -e --error --export --export-file --get-user-env --gid --gres --gres-flags -i --input -J --job-name -L --licenses -M --clusters --container -m --distribution --mail-type --mail-user --mcs-label -n --ntasks --no-requeue --ntasks-per-node -N --nodes -o --output -p --partition --power --priority --profile -q --qos -S --core-spec --signal --switches --thread-spec -t --time --time-min --uid --wckey --wrap --cluster-constraint -C --constraint -F --nodefile --mem --mincpus --reservation --tmp -w --nodelist -x --exclude --mem-per-cpu --sockets-per-node --cores-per-socket --threads-per-core -B --extra-node-info --ntasks-per-core --ntasks-per-socket --hint --mem-bind --cpus-per-gpu -G --gpus --gpu-bind --gpu-freq --gpus-per-node --gpus-per-socket --gpus-per-task --mem-per-gpu )

# This sets -x
DEBUG=false


echo_stderr() {
    echo $@ 1>&2
}

export -f echo_stderr

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
  --account=GROUP -- Which account should the slurm job be submitted under. DEFAULT: ${GROUP}
  --export={[ALL,]<environment_variables>|ALL|NONE} Default NONE as suggested by pawsey.
  --partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: ${PARTITION}
  --output -- The output filename of the job stdout. default <datetime>-<jobid>-<array_index>.stdout
  --error -- The output filename of the job stderr. default <datetime>-<jobid>-<array_index>.stderr
  --batch-nparams -- How many parameters to take for each separate job. Default: 1
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.

All other parameters, flags and arguments before '--' are passed to sbatch as is.
See: https://slurm.schedmd.com/sbatch.html

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


isin() {
    PARAM=$1
    shift
    for f in $@
    do
        if [[ "${PARAM}" == "${f}" ]]; then return 0; fi
    done

    return 1
}


check_positional() {
    FLAG="${1}"
    VALUE="${2}"
    if [ -z "${VALUE:-}" ]
    then
        echo_stderr "Positional argument ${FLAG} is missing."
        exit 1
    fi
    true
}

has_equals() {
    return $([[ "${1}" = *"="* ]])
}

split_at_equals() {
    IFS="=" FLAG=( ${1} )
    ONE="${FLAG[0]}"
    TWO=$(printf "=%s" "${FLAG[@]:1}")
    IFS="=" echo "${ONE}" "${TWO:1}"
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


# Check if we've got sbatch
if ! which sbatch > /dev/null
then
    echo_stderr "This script requires sbatch to be available on your path."
    exit 1
fi


SLURM_ARGS=( slurm )

# Here we catch our special parameters and collect the rclone ones
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
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
	    echo_stderr "ERROR: We handle the --array parameter ourselves, you can't set it"
	    echo_stderr "ERROR: Remove the \`--array\` parameter."
	    exit 1
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

	    if ! isin "${THIS_ARG}" ${VALID_SLURM_FLAGS_OPTIONAL_VALUE[@]} ${VALID_SLURM_ARGS[@]} 
            then
		echo "END of ${THIS_ARG}"
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


SCRIPT=$1
shift
POSITIONAL=( "$@" )

echo ${#POSITIONAL[@]}
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


NJOBS=$(( "${#POSITIONAL[@]}" / "${NPARAMS:-}" ))
echo "${NJOBS}"

get_index() {
    PARAM="${1}"
    NJOBS="${2}"
    INDEX="${3}"

    echo $(( "${INDEX}" + ( "${PARAM}" * "${NJOBS}" ) ))
}

ARRAY=( )
for i in $(seq 0 $(( "${NJOBS}" - 1)) )
do
    echo "I $i"
    THIS=""
    SPACE=""
    for p in $(seq 0 "$(( ${NPARAMS} - 1))")
    do
        INDEX=$(get_index "${p}" "${NJOBS}" "${i}")
	echo "INDEX ${INDEX}"
	VAL="${POSITIONAL["${INDEX}"]}"
	THIS="${THIS}${SPACE}${VAL}"
	SPACE=" "
    done
    ARRAY=( "${ARRAY[@]}" "${THIS}" )
done

read -r -d '' PY_SCRIPT <<EOF || true
import re
from os.path import basename, dirname, splitext
import sys

REGEX = re.compile(r"(?<!{){(?P<index>\\d*)(?P<cmd>[^{}]*)}(?!})")

def outer(nparams, line):
  def replacement(match):
      if (match.group("index") == "") and (nparams > 1):
	  raise ValueError("If using replacement strings with more than 1 parameter, the patterns must have an index.")

      index = match.group("index")
      if index == "":
	  index = 0
  else:
	  index = int(index) - 1

      val = ARGS[index]

      cmd = match.group("cmd")
      if cmd == "":
	  return val

      if "//" in cmd:
	return dirname(cmd)
elif "/" in cmd:
	  val = basename(val)

      for i in val.count("."):
	  val, _ = splitext(val)

      return val

for line in sys.stdin:
    line = line.strip().split()
    nparams = sys.argv[0]
    command = sys.argv[1]
    assert len(line_args) == nparams, line
    replaced_line = REGEX.sub(replacement, command)

    replaced_line = re.sub(r"(?P<paren>[{}])(?P=paren)", r"\\g<paren>", replaced_line)
    print(replaced_line)
EOF

python3 <(echo "${PY_SCRIPT}") "${NPARAMS}" "${SCRIPT}" < <(printf "%s\n" "${ARRAY[@]}")
