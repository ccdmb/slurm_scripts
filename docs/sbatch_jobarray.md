# Wrap tasks into SLURM job arrays.

`sbatch_jobarray.sh` is a wrapper around SLURM job arrays that can automatically determine how to submit a task to the queue correctly.
It will automatically determine how many array jobs to run, it can optionally pack multiple tasks into a single job array run, and is designed to run with [`pt`](./pt.md).

This strategy is good for running a lot of high-resource tasks. E.g. long jobs (say >= 3 hours) and/or a large compute allocation (say > 16 CPUs or >32GB RAM).
Unfortunately, there is a limit on how many tasks you can submit with a job-array. On pawsey you can submit up to 300 at once (last time I checked). If you have lots of small jobs, [`sbatch_parallel.sh`](./sbatch_parallel.md) might be appropriate for you.

## Instructions

This program takes commands in from stdin and submits each line as a separate task.
It automatically generates an appropriate job-array batch script from these inputs, and can also pack tasks within job-array tasks for larger jobs where shared node access isn't available.
This program also provides options for logging job exit codes, which can be used to resume the job and skip and previously successfully completed tasks.

The basic design is fairly simple and for the most part the command line arguments are passed directly to sbatch.

Here's an example using a bash HEREDOC, allocating 4 cpus per task and running each line as a separate task (which will be managed by the SLURM queue).

```
sbatch_jobarray.sh --cpus-per-task 4 <<EOF
echo "one"
echo "two"
EOF
```

If you wanted to run an MPI enabled job in the job-array, you can just add the `--ntasks 5` option as you would normally.
However, if instead you'd like to use those MPI tasks to run commands as separate tasks within the job, you can also add the `--batch-pack` flag.
To pack the job so that each job-array job will run 5 tasks, you can just specify `--ntasks 5 --batch-pack`.
The `--ntasks 5` tells slurm you'll be running 5 MPI tasks, and `--batch-pack` tells this script that it should assign one of the commands from the input queue to each of those tasks.
Say the file `cmds.sh` contained 20 commands to run.

```
sbatch_jobarray.sh --cpus-per-task 4 --ntasks 5 --batch-pack < ./cmds.sh
```

So now each job-array job will be allocated 20 CPUs (4 * 5), and there will only be 4 jobs in the job-array, because each packs 5 commands.
The job packing strategy works best if you have numerous independent commands to run and you know that they all run in roughly the same time.
If your cluster only supported single occupancy jobs (i.e. you can only allocate whole nodes, you can't just allocate 4 CPUs from that), this is a good way to submit lots of independent few-threaded jobs.
If your cluster supports shared occupancy (i.e. multiple jobs can run on a single node at once), then the only reason to use packing is if your cluster restricts the size of job-arrays and you hit that limit.
You may also consider using GNU parallel (which we also have a wrapper script for with a similar interface).

We take commands in line by line because it's the most flexible system, but it does mean that you can't submit jobs that include newlines.
If your code is fairly simple, separating the lines using semicolons `;` or `&&` should work fine.
For more complex options you might consider wrapping the bulk in a script that takes parameters.

For the simpler case, the `pt` script can be really helpful, and it was designed with this use in mind.

```
pt --nparams 'map.sh --in2 {0} --in2 {1}' *-{R1,R2}.fastq.gz | sbatch_jobarray.sh --cpus-per-task 8
```

If you use the `--batch-dry-run` flag, the program will generate a SLURM batch script for you.
You could use this batch script to submit separately with `sbatch` yourself if you wanted, e.g. if you wanted to edit something specific.
If you run the job without `--batch-dry-run`, the program submit the job with `sbatch` and echo the created SLURM job id, which you can use for job dependencies.


### Command line arguments

```
This script wraps SLURM job-arrays up in a more convenient script to run a series of commands.

It requires SLURM installed in your environment.

Parameters:
  --account=GROUP -- Which account should the slurm job be submitted under. DEFAULT: ${PAWSEY_PROJECT}
  --export={[ALL,]<environment_variables>|ALL|NONE} Default ${SLURM_EXPORT_DEFAULT} as suggested by pawsey.
  --partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: work
  --output -- The output filename of the job stdout. default "%x-%A_%4a.stdout"
  --error -- The output filename of the job stderr. default "%x-%A_%4a.stderr"
  --batch-log -- Log the job exit codes here so we can restart later. default "%x-%A_%4a.log"
  --batch-resume -- Resume the jobarray, skipping previously successful jobs according to the file provided here. <(cat *.log) is handy here.
  --batch-pack -- Pack the job so that multiple tasks run per job array job. Uses the value of --ntasks to determine how many to run per job.
  --batch-dry-run -- Print the command that will be run and exit.
  --batch-module -- Include this module the sbatch script. Can be specified multiple times.
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.
  --batch-version -- Print the version and exit.

All other parameters, flags and arguments are passed to sbatch as is.
See: https://slurm.schedmd.com/sbatch.html

Note: you can't provide the --array flag, as this is set internally and it will raise an error.


For more complex scripts, I'd suggest wrapping it in a separate script.
Note that unlike GNU parallel and srun, we don't support running functions.
```
