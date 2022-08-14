# Wrap tasks into SLURM job arrays.

`sbatch_jobarray.sh` is a wrapper around SLURM job arrays that can automatically determine how to submit a task to the queue correctly.
It will automatically determine how many array jobs to run, it can optionally pack multiple tasks into a single job array run, and is designed to run with `cmd_expansion.py`.

## Instructions

This program takes commands in from stdin or a file and submits each line as a separate task.
It automatically generates an appropriate job-array batch script from these inputs, and can also pack tasks within job-array tasks for larger jobs where shared node access isn't available.
This program also provides options for loggin job exit codes, which can be used to resume the job and skip and previously successfully completed tasks.

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
sbatch_jobarray.sh --cpus-per-task 4 --ntasks 5 --batch-pack ./cmds.sh
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

When you run the job for real (without `--batch-dry-run`), the program will just echo the created SLURM job id, which you can use for job dependencies.
