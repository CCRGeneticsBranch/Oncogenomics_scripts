#!/usr/bin/env bash
#SBATCH --partition=norm
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=24:00:00

export PERL5LIB=/mnt/nasapps/development/perl/5.28.1/bin/perl
export R_LIBS=/mnt/nasapps/development/R/r_libs/4.2.2/
export ORACLE_HOME=/usr/lib/oracle/19.9/client64
export LD_LIBRARY_PATH=/usr/lib/oracle/19.9/client64/lib
$PWD/../preprocessProjectExpressionSurvival.pl -p $1
