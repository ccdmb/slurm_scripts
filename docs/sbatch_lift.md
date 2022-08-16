# `sbatch_lift.sh`

This script delays submission of another script until its dependency is finished.
The intended use is that if a job depends on another job, but it can't figure out what resources it needs until the other job is completed (so needs to delay submission until then), then this acts as a placeholder job dependency.

E.g. if you had a download from a server, and you wanted to create another job with resource allocation (e.g. a job array) that depended on a glob of the downloaded files (e.g. `sbatch_jobarray.sh`), then you could use this script to delay submission until that job has completed.


The script supports delaying jobs by a string, function or script.
The basic usage is

```
sbatch_lift.sh <str|fn|sh> dependency command
```

`dependency` should be in the standard [sbatch dependency syntax](https://slurm.schedmd.com/sbatch.html#OPT_dependency).
And command is either a string, an exported function or the path to a shell command.
The string is the simplest and easiest option.

```
JOBID=$(sbatch_lift str afterok:12345 'pt "map.sh {}" *.fasta | sbatch_jobarray.sh --cpus-per-task 4')
```

Note that we quote the command script in single quotes to avoid expanding any globs (otherwise there wouldn't be any point in using this command).

If you have a more complex command, the next easiest option is probably to use a function.


```
runner() {
    OUTDIR=outdir
    mkdir -p "${OUTDIR}"
    pd "map.sh {0} --out ${OUTDIR}/{0}.results" *.fasta | sbatch_jobarray.sh --cpus-per-task 4
    rm tmp*  # remove some temporary files
}

export -f runner
JOBID=$(sbatch_lift.sh fn afterok:12345 runner)
```

Note that this time we don't need to worry about the globbing expanding or quoting, and we can use variables and `$` without having to worry about escaping them.

The `sh` option works much the same except instead of putting the command in a string, you put it in a file.


## What does it do?

When the dependencies of `sbatch_lift.sh` are met, it submits the command specified.
Then any dependencies of the `sbatch_lift.sh` job are transferred to this submitted command.
So the dependency chain is retained and you can still have deferred execution.

It does this with the `scontrol` command.
Pretty neat!


## What's up with the name?

The name comes from [Haskell lifting](https://wiki.haskell.org/Lifting).
In a sense you could think of sbatch jobs as monads and their job status as a tracked state.
