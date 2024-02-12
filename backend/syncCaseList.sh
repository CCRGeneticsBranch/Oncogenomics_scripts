#!/bin/bash

file=$1
project=$2
type=$3

project_file=/var/www/html/clinomics/app/scripts/backend/project_mapping.txt
dest_path=/var/www/html/clinomics/storage/ProcessedResults
source_path=""
while IFS=$'\t' read -r -a cols
do
	p=${cols[0]}
	s=${cols[2]}
	if [[ "$project" == "$p" ]];then
		source_path=$s
		break
	fi
done < ${project_file}

while IFS=$'\t' read -r -a cols
do
	pid=${cols[0]}
	cid=${cols[1]}
	#echo -e "$pid\t$cid\t$source_path"		
	if [ "$type" == "all" ] || [ "$type" == "db" ];then
		rsync -tirm --include '*/' --include "*.txt" --include '*.tsv'  --include '*.vcf' --include "*.png" --include '*.pdf' --include "*.bwa.loh" --include "*hotspot.depth" --include "*.tmb" --include "*.status" --include "*selfSM" --include 'db/*' --include "*tracking" --include "*exonExpression*" --include "TPM_ENS/*" --include "qc/rnaseqc/*" --include "TPM_UCSC/*" --include "RSEM*/*" --include 'HLA/*' --include 'NeoAntigen/*' --include 'HLA/*' --include 'MHC_Class_I/*' --include 'sequenza/*' --include 'cnvkit/*' --include 'cnvTSO/*' --include '*fastqc/*' --exclude "TPM_*/" --exclude "log/" --exclude "igv/" --exclude "topha*/" --exclude "fusion/*" --exclude "calls/" --exclude '*' ${source_path}${pid} ${dest_path}/${project}/${pid}
	fi
	if [ "$type" == "all" ] || [ "$type" == "bam" ];then
		if [[ $project == "compass_tso500" ]];then
			rsync -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*.bam*' --exclude '*' ${source_path}${pid}/${cid} ${dest_path}/${project}/${pid}
		else	
			rsync -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*bwa.final.squeeze.bam*' --include '*star.final.squeeze.bam*' --exclude '*' ${source_path}${pid}/${cid} ${dest_path}/${project}/${pid}
		fi
	fi	
done < ${file}



