#!/bin/bash -l
### Guppy can utilize one node
#SBATCH --nodes=1
### Each node on Topaz has 2 GPUs, we only request 1 though as my tests have shown that the additional GPU gives us a 10-15% boost, but we're chareged 2x the amount of service units
#SBATCH --gres=gpu:1
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks-per-socket=1
#SBATCH --mem=150gb
#SBATCH --time=24:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# Load the necessary modules
module load singularity
module load cuda

# Image from https://hub.docker.com/r/jwdebler/guppy-gpu/tags
# Downloaded via singularity pull docker://jwdebler/guppy-gpu:4.2.2
# As of version 4.2.2 you'll need to include `--min_score_mid_barcodes 60`
# to make it work like previous versions, as they changed the default setting.

# Adjust flocell, kit and barcode as required. 

srun -n 1 --export=all --gres=gpu:1 \
singularity exec --nv /group/y95/jdebler/guppy-gpu_4.2.2.sif guppy_basecaller \
-i /scratch/y95/jdebler/input/fast5 \
-s /scratch/y95/jdebler/output/fastq \
--flowcell FLO-MIN106 \
--kit SQK-LSK109 \
--barcode_kits EXP-NBD104 \
--trim_barcodes \
--detect_mid_strand_barcodes \
--min_score_mid_barcodes 60 \
--compress_fastq \
-x cuda:all
