#!/usr/bin/env bash
#SBATCH --partition=norm
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=24:00:00

#example: sbatch /mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/submitPreprocessProject.sh /mnt/projects/CCR-JK-oncogenomics/static/ProcessedResults/update_list/compass_exome_db_20220405-233934_caselist.txt chouh@nih.gov https://oncogenomics.ccr.cancer.gov/production/public
export PERL5LIB=/mnt/nasapps/development/perl/5.28.1/bin/perl
export R_LIBS=/mnt/nasapps/development/R/r_libs/4.2.2/
export ORACLE_HOME=/usr/lib/oracle/19.9/client64
export LD_LIBRARY_PATH=/usr/lib/oracle/19.9/client64/lib
$PWD/../preprocessProjectMaster.pl -p $1 -e $2 -u $3 -m -g
