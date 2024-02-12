app_home=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics
ref_file=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/public/ref/hg19.fasta
in_file=${app_home}/storage/ProcessedResults/processed_DATA/0A4HMC/20180314/OS_0A4HMC_T1R_T/OS_0A4HMC_T1R_T.star.final.bam
in_file=$1
bn="${in_file%.*}"
out_file=${bn}.squeeze.bam
app/bin/bamUtil$ bin/bam squeeze --in ${in_file} --out ${out_file} --refFile ${ref_file} --rmTags "PG:Z;RG:Z;BI:Z;BD:Z"
module load samtools
samtools index ${out_file}