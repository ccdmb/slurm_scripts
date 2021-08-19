- [CCDM Slurm Script Collection](#ccdm-slurm-script-collection)
  * [GPU accelerated basecalling with Guppy](#gpu-accelerated-basecalling-with-guppy)
    + [Running Guppy on Topaz (high accuracy mode, 1 GPU per node)](#running-guppy-on-topaz--high-accuracy-mode--1-gpu-per-node-)
      - [without demultiplexing (single sample for example)](#without-demultiplexing--single-sample-for-example-)
      - [with demultiplexing (barcoded samples)](#with-demultiplexing--barcoded-samples-)
    + [Running Guppy on Topaz (super accuracy mode, 2 GPUs per node)](#running-guppy-on-topaz--super-accuracy-mode--2-gpus-per-node-)
      - [without demultiplexing](#without-demultiplexing)
      - [with demultiplexing](#with-demultiplexing)
        * [merging output after basecalling (barcoded)](#merging-output-after-basecalling--barcoded-)
        * [merging output after basecalling (not barcoded)](#merging-output-after-basecalling--not-barcoded-)

# CCDM Slurm Script Collection

A shared repository for working slum scripts

## GPU accelerated basecalling with Guppy 

Since the latest release of Guppy (5.0.7) it has inbuilt bonito models, which increase accuracy of the basecalls, but takes about 3 times longer to call. If you want to use 'high accuracy' mode, one GPU per node is enough to call a full flowcell run in about 10 hours. Therefore you can leave all your fast5 files in a single directory. If you want to use the new 'super accuracy' mode though, you might run into walltime issues. Therefore we are utilizing both GPUs per node. In order to do that however, we need to split the input files and run separate instances of Guppy on each directory.

### Running Guppy on Topaz (high accuracy mode, 1 GPU per node)

#### without demultiplexing (single sample for example)

Copy and paste the following code into a textfile on topaz and edit the location of your input files and where you want the output files to go:

```
#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks-per-socket=1
#SBATCH --mem=150gb
#SBATCH --time=12:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# Load the necessary modules
module load singularity
module load cuda

# Image from https://hub.docker.com/r/jwdebler/guppy-gpu/tags
# Downloaded via 'singularity pull docker://jwdebler/guppy-gpu:5.0.11' or use the one in my group folder
# As of version 4.2.2 you'll need to include `--min_score_mid_barcodes 60`
# to make it work like previous versions, as they changed the default setting.

# Adjust flocell and kit as required. 
# FLO-MIN106 is the R9.4.1 series flowcell that we usually use

srun -n 1 --export=all --gres=gpu:1 \
singularity exec --nv /group/y95/jdebler/guppy-gpu_5.0.11.sif guppy_basecaller \
-i /scratch/y95/jdebler/folder_with_fast5_files \
-s /scratch/y95/jdebler/output_folder \
--flowcell FLO-MIN106 \
--kit SQK-LSK109 \
--compress_fastq \
-x cuda:all
```

#### with demultiplexing (barcoded samples)

```
#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks-per-socket=1
#SBATCH --mem=150gb
#SBATCH --time=12:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# Load the necessary modules
module load singularity
module load cuda

# Image from https://hub.docker.com/r/jwdebler/guppy-gpu/tags
# Downloaded via 'singularity pull docker://jwdebler/guppy-gpu:5.0.7' or use the one in my group folder
# As of version 4.2.2 you'll need to include `--min_score_mid_barcodes 60`
# to make it work like previous versions, as they changed the default setting.

# Adjust flocell, kit and barcode as required. 
# FLO-MIN106 is the R9.4.1 series flowcell that we usually use
# EXP-NBD104 is barcodes 1-12, EXP-NBD114 is barcodes 13-24

srun -n 1 --export=all --gres=gpu:1 \
singularity exec --nv /group/y95/jdebler/guppy-gpu_5.0.11.sif guppy_basecaller \
-i /scratch/y95/jdebler/folder_with_fast5_files \
-s /scratch/y95/jdebler/output_folder \
--flowcell FLO-MIN106 \
--kit SQK-LSK109 \
--barcode_kits EXP-NBD104 \
--trim_barcodes \
--detect_mid_strand_barcodes \
--min_score_mid_barcodes 60 \
--compress_fastq \
-x cuda:all
```

### Running Guppy on Topaz (super accuracy mode, 2 GPUs per node)

#### without demultiplexing

```
#!/bin/bash -l
#SBATCH --ntasks=2
#SBATCH --nodes=1
#SBATCH --ntasks-per-socket=1
#SBATCH --gres=gpu:2
#SBATCH --time=24:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# In order to run this you need to split your fast5 files into 2 separate directories called 'input_0' and 'input_1'
# This config uses the new bonito derived 'super_accurate' model and will therefore be 3 times slower than the 'hac' model.

# Image from https://hub.docker.com/r/jwdebler/guppy-gpu/tags
# Downloaded via 'singularity pull docker://jwdebler/guppy-gpu:5.0.7' or use the one in my group folder
# As of version 4.2.2 you'll need to include `--min_score_mid_barcodes 60`
# to make it work like previous versions, as they changed the default setting.

# Load the necessary modules
module load singularity
module load cuda

# Adjust config as required. 

for tagID in $(seq 0 1); do
    srun -u -N 1 -n 1 --mem=0 --gres=gpu:1 --exclusive \
    singularity exec --nv /group/y95/jdebler/guppy-gpu_5.0.11.sif guppy_basecaller \
    -i /scratch/y95/jdebler/input_${tagID}/ \
    -s /scratch/y95/jdebler/output_guppy507/${tagID} \
    -c dna_r9.4.1_450bps_sup.cfg \
    --compress_fastq \
    -x cuda:all &
done
wait
```

#### with demultiplexing

```
#!/bin/bash -l
#SBATCH --ntasks=2
#SBATCH --nodes=1
#SBATCH --ntasks-per-socket=1
#SBATCH --gres=gpu:2
#SBATCH --time=24:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# In order to run this you need to split your fast5 files into 2 separate directories called 'input_0' and 'input_1'
# This config uses the new bonito derived 'super_accurate' model and will therefore be 3 times slower than the 'hac' model.

# Image from https://hub.docker.com/r/jwdebler/guppy-gpu/tags
# Downloaded via 'singularity pull docker://jwdebler/guppy-gpu:5.0.7' or use the one in my group folder
# As of version 4.2.2 you'll need to include `--min_score_mid_barcodes 60`
# to make it work like previous versions, as they changed the default setting.

# Load the necessary modules
module load singularity
module load cuda

# Adjust barcode kit and config as required. 

for tagID in $(seq 0 1); do
    srun -u -N 1 -n 1 --mem=0 --gres=gpu:1 --exclusive \
    singularity exec --nv /group/y95/jdebler/guppy-gpu_5.0.11.sif guppy_basecaller \
    -i /scratch/y95/jdebler/input_${tagID}/ \
    -s /scratch/y95/jdebler/output_guppy507/${tagID} \
    -c dna_r9.4.1_450bps_sup.cfg \
    --barcode_kits EXP-NBD104 \
    --trim_barcodes \
    --detect_mid_strand_barcodes \
    --min_score_mid_barcodes 60 \
    --compress_fastq \
    -x cuda:all &
done
wait
```

##### merging output after basecalling (barcoded)

Since we had to split the input fast5 files for parallel processing, we also end up with the output files in different directories.
In order to merge the output files and rename them (if they were multiplexed), copy following code into a shell script and run it from inside the output directory you defined in your slurm script. 

```
#!/usr/bin/bash

for dir in */pass/*
    do
    x=$(basename $dir)
    echo 'found' $x 'in' $dir', merging into' $x'.fastq.gz'
    cat ${dir}/*.fastq.gz >> ${x}.fastq.gz
    done
```
I called it `merge.sh`, you can also just get it from `/group/y95/jdebler/merge.sh`.

For example:

```
ls

drwxr-sr-x 4 jdebler y95  4096 May 21 11:26 output_guppy_507
-rw-rw-r-- 1 jdebler y95  1811 May 21 12:26 slurm-147694.out
drwxr-sr-x 2 jdebler y95 32768 Apr 29 17:11 input_0
drwxr-sr-x 2 jdebler y95 24576 Apr 29 17:12 input_1

cd output_guppy_507

ls

drwxr-sr-x 5 jdebler y95 4096 May 21 12:24 0
drwxr-sr-x 5 jdebler y95 4096 May 21 12:23 1
-rwxrwxr-x 1 jdebler y95   133 May  1 07:35 merge.sh

cd 0

drwxr-sr-x 12 jdebler y95     4096 May 21 12:12 fail
drwxr-sr-x  6 jdebler y95     4096 May 21 11:26 guppy_basecaller-core-dump-db
-rw-r--r--  1 jdebler y95  5242742 May 21 11:34 guppy_basecaller_log-2021-05-21_11-26-46.log
-rw-r--r--  1 jdebler y95  5242801 May 21 11:38 guppy_basecaller_log-2021-05-21_11-34-10.log
-rw-r--r--  1 jdebler y95  5242863 May 21 11:44 guppy_basecaller_log-2021-05-21_11-38-50.log
-rw-r--r--  1 jdebler y95  5242847 May 21 11:48 guppy_basecaller_log-2021-05-21_11-44-12.log
-rw-r--r--  1 jdebler y95  5242806 May 21 11:54 guppy_basecaller_log-2021-05-21_11-48-53.log
-rw-r--r--  1 jdebler y95  5242819 May 21 12:08 guppy_basecaller_log-2021-05-21_11-54-04.log
-rw-r--r--  1 jdebler y95  5242808 May 21 12:13 guppy_basecaller_log-2021-05-21_12-08-56.log
-rw-r--r--  1 jdebler y95  5242753 May 21 12:17 guppy_basecaller_log-2021-05-21_12-13-18.log
-rw-r--r--  1 jdebler y95  5242760 May 21 12:24 guppy_basecaller_log-2021-05-21_12-17-36.log
-rw-r--r--  1 jdebler y95  1686898 May 21 12:26 guppy_basecaller_log-2021-05-21_12-24-16.log
drwxr-sr-x 12 jdebler y95     4096 May 21 11:46 pass
-rw-r--r--  1 jdebler y95 95977453 May 21 12:26 sequencing_summary.txt

cd ..

./merge.sh

found barcode01 in 0/pass/barcode01, merging into barcode01.fastq.gz
found barcode05 in 0/pass/barcode05, merging into barcode05.fastq.gz
found barcode06 in 0/pass/barcode06, merging into barcode06.fastq.gz
found barcode07 in 0/pass/barcode07, merging into barcode07.fastq.gz
found barcode08 in 0/pass/barcode08, merging into barcode08.fastq.gz
found barcode09 in 0/pass/barcode09, merging into barcode09.fastq.gz
found barcode10 in 0/pass/barcode10, merging into barcode10.fastq.gz
found barcode11 in 0/pass/barcode11, merging into barcode11.fastq.gz
found barcode12 in 0/pass/barcode12, merging into barcode12.fastq.gz
found unclassified in 0/pass/unclassified, merging into unclassified.fastq.gz
found barcode04 in 1/pass/barcode04, merging into barcode04.fastq.gz
found barcode05 in 1/pass/barcode05, merging into barcode05.fastq.gz
found barcode06 in 1/pass/barcode06, merging into barcode06.fastq.gz
found barcode07 in 1/pass/barcode07, merging into barcode07.fastq.gz
found barcode08 in 1/pass/barcode08, merging into barcode08.fastq.gz
found barcode09 in 1/pass/barcode09, merging into barcode09.fastq.gz
found barcode10 in 1/pass/barcode10, merging into barcode10.fastq.gz
found barcode11 in 1/pass/barcode11, merging into barcode11.fastq.gz
found barcode12 in 1/pass/barcode12, merging into barcode12.fastq.gz
found unclassified in 1/pass/unclassified, merging into unclassified.fastq.gz
```

`input_0` and `input_1` contain my fast5 files, `output_guppy_507` contains 2 folders, `0` and `1`, which each contain the output of the individual guppy runs. This script now goes into those directories, looks into the `pass` folder and extracts and merges the reads stored in the respective `barcodeX` folders.

##### merging output after basecalling (not barcoded)

This is a bit easier since we don't have to deal with barcode names. Simply run the following command from within the output directory:
`for file in */pass/*.fastq.gz; do echo $file; cat $file > output.fastq.gz; done`
Change `output.fastq.gz` to whatever samplename you want.
