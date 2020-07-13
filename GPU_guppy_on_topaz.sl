#!/bin/bash -l
### Guppy can utilize one node
#SBATCH --nodes=1
### Each node on Topaz has 2 GPUs, so we request both
#SBATCH --gres=gpu:2
#SBATCH --ntasks-per-node=2
#SBATCH --ntasks-per-socket=1
### Not sure how important that is, but I got it from the Pawsey docs
#SBATCH --mem=180gb
#SBATCH --time=24:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# Load the necessary modules
module load singularity
module load cuda

# Image from https://hub.docker.com/r/genomicpariscentre/guppy-gpu/tags
# Downloaded via singularity pull docker://genomicpariscentre/guppy-gpu:3.6.1
# They do not yet have guppy 4.0.11 so I built the image myself using their Dockerfile
# Adjust flocell, kit and barcode as required. 

srun -n 2 --export=all --gres=gpu:2 \
singularity exec --nv /group/y95/jdebler/guppy-gpu_4.0.11.sif \ 
guppy_basecaller \
-i /scratch/y95/jdebler/input/fast5 \
-s /scratch/y95/jdebler/output/fastq \
--flowcell FLO-MIN106 \
--kit SQK-LSK109 \
--barcode_kits EXP-NBD104 \
--trim_barcodes \
--detect_mid_strand_barcodes \
--compress_fastq \
-x cuda:all