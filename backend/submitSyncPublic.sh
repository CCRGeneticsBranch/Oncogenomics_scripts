#!/usr/bin/env bash
#SBATCH --partition=norm
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=48:00:00

#example: sbatch -o slurm_log/sync_CRUK.o -e slurm_log/sync_CRUK.e --chdir=/mnt/projects/CCR-JK-oncogenomics/static/clones/clinomics_public/app/scripts/backend /mnt/projects/CCR-JK-oncogenomics/static/clones/clinomics_public/app/scripts/backend/submitSyncPublic.sh CRUK chouh@nih.gov
./syncPublic.sh $1 $2
