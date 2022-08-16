# `sbatch_rclone.sh`

This script is a wrapper around Rclone, which automatically submits a SLURM job to the queue.
It requires Rclone and Slurm installed in your environment.

Positional arguments:

-  copy, copyto untar, tar, gunzip, gzip, sync, help, version -- The subcommand to run.
    tar and gzip based options are new to this, and work by streaming data from or
    to the remote while compressing or decompressing results.
    Decompression only works going from remote to local, compression only works the other way.
- SRC -- The source file or directory to copy. Structure is the same as rclone
- DEST -- The destination file or directory to copy. Structure is the same as rclone

Parameters:

-  --batch-group GROUP -- Which account should the slurm job be submitted under. DEFAULT: `${PAWSEY_PROJECT}`
-  --batch-partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: `copy`
-  --batch-help -- Show this help and exit.
-  --batch-debug -- Sets verbose logging so you can see what's being done.
-  --batch-rclone-module -- Specifies a module to load rclone if needed. Can take a default from environment variable `${SLURM_SCRIPTS_RCLONE_MODULE}`. If not provided we'll assume it's on your `PATH` already.
-  --batch-pigz-module -- Specifies a module to load pigz if needed. Can take a default from environment variable `${SLURM_SCRIPTS_PIGZ_MODULE}`. Only used with the tar, untar, gzip, and gunzip commands. If not provided we'll assume it's on your `PATH` already.
-  --batch-dry-run -- Shows the SLURM batch script that will be submitted and exits without actually submitting.
-  --batch-preview -- [BETA] Shows the files that will be downloaded from the server. The hope with this is that you could specify a job-array e.g before the files have actually been downloaded, but for technical reasons it's a bit difficult.

All other parameters, flags and arguments are passed to rclone as is.
If --transfers is unset, we set it to 12 (from the default of 4) which is the Pawsey recommendation.

NB. using --interactive will raise an error because interactive jobs wouldn't work in a batch job.
NB. Using --filter, --include, or --exclude will raise an error for tar or gzip subcommands.
    This may change in the future.


USAGE:

```
sbatch_rclone.sh [copy|copyto|...|version] [source] [destination] [-- ARGUMENTS]
# Note the 3 positional arguments must all come before the --flags etc.
```

Examples:

```
sbatch_rclone.sh copy y95:myproject/files/ ./input --exclude "*.gff3"
sbatch_rclone.sh copy ./results y95:myproject/
```

`copyto` is basically the same as `copy` except if you're only copying a single file you can re-name the file.
Otherwise it really just puts it in folders. Probably best to use copy and rename the file if it's ambiguous as to whether you're moving one or multiple files.

`sync` works, but is a bit dangerous.
If you forget to properly specify the destination it will delete anything that isn't in your source, so you could lose a lot of data.

I made the following mistake when testing it out.

```
sbatch_clone.sh sync ./local y95:myproject
```

This deleted EVERYTHING in my bucket and wrote whatever was in local there.
Make sure you know whay you're doing with this one.


For `copy`, `copyto` and `sync` commands copying data from remote to local, you can use the `--batch-preview` flag, which should return a list of what files it expects to create on your local drive.
This is intended to work so that you can start job dependencies on your `rclone` download before the download has actually started.
In practise, it's hard to be accurate so this behaviour should be checked before you run it.

```
sbatch_clone copy y95:myproject/files ./input --exclude "*.gff3"
# ./input/file1.fasta
# ./input/file1.txt
# ./input.file2.fasta
# ./input/file2.txt
# etc
```


```
sbatch_rclone gunzip y95:myproject/sequences.fasta.gz ./sequences.fasta
## it will automatically gunzip here.

sbatch_rclone gzip large_blast_results.tsv y95:myproject/large_blast_results.tsv.gz
## gzip only works from local to remote, gunzip only works from remote to local.
```


```
sbatch_rclone untar y95:myproject/genomes.tar.gz ./genomes/
# This will uncompress and extract the files in genomes.tar.gz
# Note that the placement of the actual files will depend on how the tarball was created in the first place.

sbatch_rclone tar ./new_genomes y95:myproject/new_genomes.tar.gz
# Like gzip, tar only works going from local to remote, and untar remote to local.
# Note that this will pack the files in new_genomes, not the parent folder.
# This means that when you untar them later all of the files will be dumped in your current directory.
# In the untar above we specified a folder as the destination which the script will create (if necessary) and `cd` into before untar-ing the file.
```
