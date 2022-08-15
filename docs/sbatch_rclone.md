# `sbatch_rclone.sh`

This script is a wrapper around Rclone, which automatically submits a SLURM job to the queue.
It requires Rclone and Slurm installed in your environment.

Positional arguments:
  copy, copyto untar, tar, gunzip, gzip, sync, help, version -- The subcommand to run.
    tar and gzip based options are new to this, and work by streaming data from or
    to the remote while compressing or decompressing results.
    Decompression only works going from remote to local, compression only works the other way.

  SRC -- The source file or directory to copy. Structure is the same as rclone
  DEST -- The destination file or directory to copy. Structure is the same as rclone

Parameters:
  --batch-group GROUP -- Which account should the slurm job be submitted under. DEFAULT: `${GROUP}`
  --batch-partition -- Which queue/partition should the slurm job be submitted to. DEFAULT: `${PARTITION}`
  --batch-help -- Show this help and exit.
  --batch-debug -- Sets verbose logging so you can see what's being done.
  --batch-rclone-module -- Specifies a module to load rclone if needed. Can take a default from environment variable `${SLURM_SCRIPTS_RCLONE_MODULE}`. If not provided we'll assume it's on your `PATH` already.
  --batch-pigz-module -- Specifies a module to load pigz if needed. Can take a default from environment variable `${SLURM_SCRIPTS_PIGZ_MODULE}`. Only used with the tar, untar, gzip, and gunzip commands. If not provided we'll assume it's on your `PATH` already.
  --batch-dry-run -- Shows the SLURM batch script that will be submitted and exits without actually submitting.
  --batch-preview -- [BETA] Shows the files that will be downloaded from the server. The hope with this is that you could specify a job-array e.g before the files have actually been downloaded, but for technical reasons it's a bit difficult.

All other parameters, flags and arguments are passed to rclone as is.
If --transfers is unset, we set it to 12 (from the default of 4) which is the Pawsey recommendation.

NB. using --interactive will raise an error because interactive jobs wouldn't work in a batch job.
NB. Using --filter, --include, or --exclude will raise an error for tar or gzip subcommands.
    This may change in the future.
