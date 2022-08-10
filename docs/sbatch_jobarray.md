# Wrap tasks into SLURM job arrays.

`sbatch_jobarray.sh` is a wrapper around SLURM job arrays that can automatically determine how to submit a task to the queue correctly.
It will automatically determine how many array jobs to run, it can optionally pack multiple tasks into a single job array run, and supports parameter expansion with `cmd_expansion.py`.

Instructions

Generate some example files to demonstrate with

```
mkdir dir1 dir2

touch {dir1,dir2}/{one,two,three}-{R1,R2}.fastq.gz
```

I'm using paired fastq reads as an example because it is a common use case for some of the grouping options supported.
Throughout the guide, we'll use a hypothetical command `map.sh` as an example.

```
# If you wanted to actually run the commands, this would create an appropriate dummy script.
echo -e '#!/usr/bin/env bash\necho $@' > ./map.sh
chmod a+x ./map.sh
```

Note that throughout the document we will use the `--batch-dry-run` parameter, which will just print the batch script to the stdout instead of submitting the job to SLURM.

`sbatch_jobarray.sh` supports incoming files as either a globbed pattern or a TSV table.

As a basic example, if you wanted to run a command for each input file using a globbing pattern:
```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 -- map.sh */*.fastq.gz
```

This will create a batch script that loads the the `mapper/1.0` module, and runs map.sh for each file in the glob pattern as the first argument.

If we wanted to be more explicit about how the command should be run, we could also use the expansion rules:

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 -- 'map.sh --infile {} --verbose' */*.fastq.gz
```

In this case, the input file will be provided where `{}` is.

All arguments supported by SLURM `sbatch` are passed on to the scheduler, so if you wanted to specify the queue and to use 4 CPUs per task, you could do:

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --partition y95 --cpus-per-task 4 -- map.sh */*.fastq.gz
```

The only arguments that aren't supported are `--array` (because we use this), and some of the `--ntasks-per-` specifications (i.e. `--ntasks-per-{core,gpu,socket}` etc).


Lets say we want to treat these fastq files as read pairs.
With globbing, it's as simple as providing the `--batch-nparams` argument and taking a bit of care with the glob.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-nparams 2 --partition y95 --cpus-per-task 4 -- map.sh */*-{R1,R2}.fastq.gz
```

This will run `map.sh dir1/one-R1.fastq.gz dir1/one-R2.fastq.gz` etc.

The globbing pattern is important, to get the glob expansion correct you should use brace expansion as above `{R1,R2}` and use it in only one place.
The pattern above will expand to `dir1/one-R1.fastq.gz dir1/three-R1.fastq.gz dir1/two-R1.fastq.gz dir2/one-R1.fastq.gz dir2/three-R1.fastq.gz dir2/two-R1.fastq.gz dir1/one-R2.fastq.gz dir1/three-R2.fastq.gz dir1/two-R2.fastq.gz dir2/one-R2.fastq.gz dir2/three-R2.fastq.gz dir2/two-R2.fastq.gz` (i.e. all R2s come after all R1s).

Explicitly providing the arguments rather than using the glob is fine, but you must make sure the order is arranged as above.
To use more than two parameters (e.g. 3), you can just use `--batch-nparams 3` and `*/*-{R1,R2,UNMAPPED}.fastq.gz`, for example.
Make sure there is no space in the braces, and see the [bash documentation](https://www.gnu.org/software/bash/manual/html_node/Brace-Expansion.html).


Just like with one argument, you can customise how the parameters are provided to the command using the cmd expansion script.
However, in this case you must explicitly provide the index to use (in the single parameter case, it just default to the first parameter).
Indexing is 0 based (start inclusive and end exclusive), just like python.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-nparams 2 --partition y95 --cpus-per-task 4 -- 'map.sh --r1 {0} --r2 {1}' */*-{R1,R2}.fastq.gz
```


A lot of the real power with this approach comes from the cmd_expansion.py syntax, which gives you some nice options for manipulating filenames.
Lets say I want to use the filenames to create an output filename, i can do that.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-nparams 2 --partition y95 --cpus-per-task 4 -- 'map.sh --outfile {0r/-R1\.fastq\.gz/}.bam --r1 {0} --r2 {1}' */*-{R1,R2}.fastq.gz
```

Will run `map.sh --outfile dir1/one.bam --r1 dir1/one-R1.fastq.gz --r2 dir1/one-R2.fastq.gz` for example.

You can get even more exotic if you use the array syntax, which is described in more detail in the `cmd_expansion.py` docs.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-nparams 2 --partition y95 --cpus-per-task 4 -- 'map.sh --outfile {@pr/-R/}.bam --r1 {0} --r2 {1}' */*-{R1,R2}.fastq.gz
```

Runs exactly the same thing as the last one, but by finding the common prefix between all parameters and stripping `-R` from the end.

The array syntax becomes more useful when you need to group data.
Say you had to split a sequencing run over multiple flow cells, and you don't want to merge the fastq files before aligning so that you can get proper read group information.
You can group some kind of data in the glob to extract how the files should be combined.
In this case, i'm going to pretend that the directories are common samples that should be grouped. I'll provide that dirname to the `--batch-group` parameter.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-group '{0d}' --batch-nparams 2 --partition y95 --cpus-per-task 4 -- 'map.sh --outfile {0d}.bam --r1 {0@} --r2 {1@}' */*-{R1,R2}.fastq.gz
```

This will run

```
map.sh --outfile dir1.bam --r1 dir1/one-R1.fastq.gz dir1/three-R1.fastq.gz dir1/two-R1.fastq.gz --r2 dir1/one-R2.fastq.gz dir1/three-R2.fastq.gz dir1/two-R2.fastq.gz
map.sh --outfile dir2.bam --r1 dir2/one-R1.fastq.gz dir2/three-R1.fastq.gz dir2/two-R1.fastq.gz --r2 dir2/one-R2.fastq.gz dir2/three-R2.fastq.gz dir2/two-R2.fastq.gz
```

What's happening is that I group by the directory name from the first parameter `{0d}`, and I provide all of the grouped first array parameter `{0@}` and second parameter array `{1@}` to the `--r1/--r2` parameters.
By default, arrays will be joined using a single space, but you can also customise this.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-group '{0d}' --batch-nparams 2 --partition y95 --cpus-per-task 4 -- 'map.sh --outfile {0d}.bam --r1 {0@j/,/} --r2 {1@j/,/}' */*-{R1,R2}.fastq.gz
```

```
map.sh --outfile dir1.bam --r1 dir1/one-R1.fastq.gz,dir1/three-R1.fastq.gz,dir1/two-R1.fastq.gz --r2 dir1/one-R2.fastq.gz,dir1/three-R2.fastq.gz,dir1/two-R2.fastq.gz
map.sh --outfile dir2.bam --r1 dir2/one-R1.fastq.gz,dir2/three-R1.fastq.gz,dir2/two-R1.fastq.gz --r2 dir2/one-R2.fastq.gz,dir2/three-R2.fastq.gz,dir2/two-R2.fastq.gz
```


Ok. So the globbing pattern is handy but it won't necessarily meet all of your needs.
You can also provide a tab separated text file providing the parameters explicitly.


E.g. in the paired run option above, you could have a file `reads.tsv` like below:

```
dir1/one-R1.fastq.gz    dir1/one-R2.fastq.gz
dir1/three-R1.fastq.gz  dir1/three-R2.fastq.gz
dir1/two-R1.fastq.gz    dir1/two-R2.fastq.gz
dir2/one-R1.fastq.gz    dir2/one-R2.fastq.gz
dir2/three-R1.fastq.gz  dir2/three-R2.fastq.gz
dir2/two-R1.fastq.gz    dir2/two-R2.fastq.gz
```

And then you can run pretty much the same command as above, but indead of providing the `--batch-nparams` and a glob, you can just specify this file to `--batch-file` and it will take the parameters from the columns.

```
sbatch_jobarray.sh --batch-dry-run --batch-module mapper/1.0 --batch-file ./reads.tsv --partition y95 --cpus-per-task 4 -- 'map.sh --outfile {0r/-R1\.fastq\.gz/}.bam --r1 {0} --r2 {1}'
```

You could even add extra metadata columns (e.g. FASTQ read groups) and use that as a grouping pattern, which you can just access and manipulate like you did with the files.


So there's a lot of flexibility in the system, and it will all automatically submit the appropriate number of jobs depending on grouping parameters etc.


When you run the job for real (without `--batch-dry-run`), the program will just echo the created SLURM job id, which you can use for job dependencies.
