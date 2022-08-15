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

# Image from hhttps://hub.docker.com/r/jwdebler/guppy-gpu/tags
# Downloaded via singularity pull docker://jwdebler/megalodon_guppy:2210.452.2

# Adjust flocell, kit and barcode as required.

srun -n 1 --export=all --gres=gpu:1 \
singularity exec --nv /group/y95/jdebler/meg234_guppy_5011_latest.sif megalodon /scratch/y95/username/folder_with_fast5_files/ \
--guppy-server-path /home/ont-guppy/bin/guppy_basecall_server \
--guppy-params "--chunk_size 1000" \
--guppy-config dna_r9.4.1_450bps_modbases_5mc_hac.cfg \
--outputs mod_mappings mods \
--reference /scratch/y95/username/reference/genome.fasta \
--mod-motif m CG 0 \
--output-directory /scratch/y95/username/megalodon_output \
--overwrite \
--sort-mappings \
--mod-map-emulate-bisulfite \
--mod-map-base-conv C T --mod-map-base-conv m C \
--devices cuda:all \
--processes 16
