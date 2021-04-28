#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks-per-socket=1
#SBATCH --mem=150gb
#SBATCH --time=10:00:00
#SBATCH --partition=gpuq
#SBATCH --account=y95
#SBATCH --export=NONE

# Load the necessary modules
module load singularity
module load cuda/10.2

# Image from https://hub.docker.com/r/jwdebler/bonito/tags
# Downloaded via 'singularity pull docker://jwdebler/bonito:0.38.4'
# you have to set a fake home directory path, somewhere your user has write access
# this is the '-B /some/existing/path:$HOME'
# replace 'dna_r9.4.1' with 'dna_r10.3' if you used an R10 series flowcell

srun -n 1 --export=all --gres=gpu:1 \
singularity exec --nv -B /scratch/y95/jdebler/:$HOME /group/y95/jdebler/bonito_0.38.4.sif bonito basecaller \
dna_r9.4.1 \
--recursive /scratch/y95/jdebler/fast5/ > /scratch/y95/jdebler/output.fasta
