#!/bin/bash
projects=( "clinomics":"tgen:/projects/Clinomics/ProcessedResults/" "processed_DATA":"biowulf2:/data/khanlab/projects/processed_DATA/" "cmpc":"biowulf2:/data/Clinomics/Analysis/CMPC/" "nbl":"biowulf2:/data/khanlab/projects/NBL/" "rms_panel":"biowulf2:/data/khanlab/projects/RMS_Panel/" )
#projects=( "clinomics":"tgen:/projects/Clinomics/ProcessedResults/" )
#projects=( "omics":"biowulf2:/data/khanlab/projects/DNASeq/" )
#projects=( "cmpc_clinical":"biowulf2:/data/Clinomics/Analysis/CMPC_clinical/" )
#projects=( "processed_DATA":"biowulf2:/data/khanlab/projects/processed_DATA/" "cmpc":"biowulf2:/data/Clinomics/Analysis/CMPCResults/" "cmpc_clinical":"biowulf2:/data/Clinomics/Analysis/CMPC_clinical/" "rms":"biowulf2:/data/khanlab/projects/RMS_Exome/" "nbl_panel":"biowulf2:/data/khanlab/projects/NBL_Panel/" "rms_panel":"biowulf2:/data/khanlab/projects/RMS_Panel/" )
home='/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.data'
data_home=${home}/ProcessedResults
script_home=${home}/scripts/backend

for p in "${projects[@]}"
do 	
	project=${p%%:*}
	source_path=${p#*:}
	project_home=${data_home}/${project}
	if [ ! -d ${project_home} ]; then
		mkdir ${project_home}
	fi
	prefix=${data_home}/update_list/load_${project}_`date +"%Y%m%d-%H%M%S"`
	#echo ${prefix}
        update_list=${prefix}.txt
        log_file=${prefix}.log
	date >> ${log_file}
	echo "[ Processing project: $project ]" >> ${log_file}
	#echo "[ Processing project: $project ]"
	#rsync -tirm --size-only --include '*/' --include '*.vcf' --include '*actionable.txt' --include "*coding.rare.txt" --include "*consolidated_QC.txt" --include "*RnaSeqQC.txt" --include "*genotyping.txt" --include '*bwa.final.bam*' --include '*star.final.bam*' --include 'db/*' --include '*png' --include "*tracking" --include "*exonExpression*" --exclude "log/" --exclude "igv/" --exclude "topha*/" --exclude "fusion/" --exclude "calls/" --exclude '*' ${source_path} ${project_home} >>${log_file} 2>&1
	egrep '^>' ${log_file} | cut -d ' ' -f 2 > ${update_list}
	#find ${data_home}/ -empty -type d -exec rmdir {} \; 2>/dev/null
	date >> ${log_file}
	#LC_ALL="en_US.utf8" ${script_home}/loadVarPatients.pl -i ${project_home} -l ${update_list} 2>&1 1>>${log_file}
	LC_ALL="en_US.utf8" ${script_home}/loadVarPatients.pl -i ${project_home} -t exp 2>&1 1>>${log_file}
	#LC_ALL="en_US.utf8" ${script_home}/loadVarPatients.pl -i ${project_home} -t variants 2>&1 1>>${log_file}
	chmod -f -R 775 ${project_home}
	echo "done" >> ${log_file}
done
