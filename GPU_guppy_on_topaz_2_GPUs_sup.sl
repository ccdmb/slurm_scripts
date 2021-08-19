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
# Downloaded via 'singularity pull docker://jwdebler/guppy-gpu:5.0.11'
# As of version 4.2.2 you'll need to include `--min_score_mid_barcodes 60`
# to make it work like previous versions, as they changed the default setting.

# Load the necessary modules
module load singularity
module load cuda

for tagID in $(seq 0 1); do
        srun -u -N 1 -n 1 --mem=0 --gres=gpu:1 --exclusive \
    singularity exec --nv /group/y95/jdebler/guppy-gpu_5.0.11.sif guppy_basecaller \
    -i /scratch/y95/jdebler/input_${tagID}/ \
    -s /scratch/y95/jdebler/output_guppy5011/${tagID} \
    -c dna_r9.4.1_450bps_sup.cfg \
    --barcode_kits EXP-NBD104 \
    --trim_barcodes \
    --detect_mid_strand_barcodes \
    --min_score_mid_barcodes 60 \
    --compress_fastq \
    -x cuda:all &
done
wait
