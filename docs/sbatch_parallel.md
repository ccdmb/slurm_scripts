# Wrap tasks into SLURM a single job run as a GNU parallel queue.

`sbatch_parallel.sh` is a wrapper around SLURM submitting tasks using GNU parallel.
It has the same basic API as [`sbatch_jobarray.sh`](./sbatch_jobarray.md) and is designed to run with [`pt`](./pt.md).

This strategy works best if you have a lot of jobs to run (say > 100), that are relatively small (e.g. single threaded), but may have different job runtimes while still being relatively quick (say <= 3 hours). It's also best if you allocate substantially fewer resources to the process than there are tasks.
E.g. if you had 200 tasks to run, run it so that ~10-20 tasks can run at once. If you allocate a lot of resources then you'll be wasting CPU time if one or two jobs take a very long time, but others are quite short. If you have long running tasks or tasks that require a lot of resources (e.g. a whole node), it's better to use a jobarray as these will stop billing you for CPU time as soon as they complete (assuming you aren't packing jobs).

## Instructions

This program takes commands in from stdin or a file and submits each line as a separate task.
This program also provides options for logging job exit codes, which can be used to resume the job and skip and previously successfully completed tasks.

For now we use GNU parallel's own logging to decide whether a task has been successfully completed, so the log files are not compatible with `sbatch_jobarray.sh`.

The basic design is fairly simple and for the most part the command line arguments are passed directly to sbatch.
You can think of this script as creating a mini-cluster, and GNU parallel will submit the tasks as others finish.
So you specify how many tasks you would like to run concurrently using `--ntasks`, and how many cpus each task should have access to with `--cpus-per-task`. Then you can provide as many commands as you want to STDIN, and parallel will keep submitting jobs within this allocation (without you having to wait in the SLURM queue, and without limits on how many jobs you can run [job arrays are capped at 300]).

Here's an example using a bash HEREDOC, allocating 4 cpus per task and running each line as a separate task (which will be managed by the SLURM queue).

```
sbatch_parallel.sh --ntasks 2 --cpus-per-task 4 <<EOF
echo "one"
echo "two"
echo "three"
echo "four"
EOF
```

Will run 2 tasks running in parallel, and `echo three` will be submitted whenever either one or three is finished.
Unfortunately because GNU parallel is using MPI to run the tasks internally, you cannot submit MPI tasks to be run with this method.

We take commands in line by line because it's the most flexible system, but it does mean that you can't submit jobs that include newlines.
If your code is fairly simple, separating the lines using semicolons `;` or `&&` should work fine.
For more complex options you might consider wrapping the bulk in a script that takes parameters.

For the simpler case, the `pt` script can be really helpful, and it was designed with this use in mind.

```
pt --nparams 'map.sh --in2 {0} --in2 {1}' *-{R1,R2}.fastq.gz | sbatch_parallel.sh --cpus-per-task 1 --ntasks 2
```

When you run the job for real (without `--batch-dry-run`), the program will just echo the created SLURM job id, which you can use for job dependencies.


### Command line arguments

```
This script wraps SLURM job-arrays up in a more convenient way to perform embarassing parallelism from a glob of files.
All

It requires SLURM installed in your environment.

Parameters:
  --account=GROUP -- Which account should the slurm job be submitted under. DEFAULT: `${PAWSEY_PROJECT}`
  --export={[ALL,]<environment_variables>|ALL|NONE} Default ${SLURM_EXPORT_DEFAULT} as suggested by pawsey.
  --partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: ${SLURM_PARTITION_DEFAULT}
  --output -- The output filename of the job stdout. default "%x-%A_%4a.stdout"
  --error -- The output filename of the job stderr. default "%x-%A_%4a.stderr"
  --batch-log -- Log the job exit codes here so we can restart later. default "%x-%A_%4a.log"
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
```
