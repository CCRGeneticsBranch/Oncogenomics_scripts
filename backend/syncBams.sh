#!/bin/bash
target_project=$1
EXPECTED_ARGS=1
E_BADARGS=65
if [ $# -ne $EXPECTED_ARGS ]
then
	echo "Usage: `basename $0` {target project}"
	exit $E_BADARGS
fi
#projects=( "clinomics":"tgen:/projects/Clinomics/ProcessedResults/" "processed_DATA":"biowulf2:/data/khanlab/projects/processed_DATA/" "cmpc":"biowulf2:/data/Clinomics/Analysis/CMPC/" "nbl":"biowulf2:/data/khanlab/projects/NBL/" "rms_panel":"biowulf2:/data/khanlab/projects/RMS_Panel/" "guha":"biowulf2:/data/GuhaData/" "alex":"biowulf2:/data/AlexanderP3/Alex/" "collobaration":"biowulf2:/data/khanlab2/collobaration_DATA/")
#projects=( "guha":"biowulf2:/data/GuhaData/")
data_home=/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults
script_home_dev=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/scripts/backend

prefix=${data_home}/update_list/${project}_`date +"%Y%m%d-%H%M%S"`
case_log=${prefix}_case.log
project_file=$script_home_dev/project_mapping_bams.txt

while IFS=$'\t' read -r -a cols
do
	project=${cols[0]}
	source_path=${cols[1]}
	if [ "$target_project" == "$project" ] || [ "$target_project" == "all" ]
	then
		
		project_home=${data_home}/${project}
		if [ ! -d ${project_home} ]; then
			mkdir ${project_home}
		fi
		prefix=${data_home}/update_list/${project}_bam_`date +"%Y%m%d-%H%M%S"`
		update_list=${prefix}.txt
		log_file=${prefix}.log
		date >> ${log_file}
		echo "[ Syncing project: $project ]" >> ${log_file}
		#rsync -tirm --size-only --include '*/' --include '*bwa.final.squeeze.bam*' --include '*star.final.squeeze.bam*' --exclude "log/" --exclude "igv/" --exclude "topha*/" --exclude "fusion/" --exclude "calls/" --exclude '*' ${source_path} ${project_home} >>${log_file} 2>&1
		rsync -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*bwa.final.squeeze.bam*' --include '*star.final.squeeze.bam*' --exclude '*' ${source_path} ${project_home} >>${log_file} 2>&1
		egrep '^>' ${log_file} | cut -d ' ' -f 2 > ${update_list}
		date >> ${log_file}
		chmod -f -R 775 ${project_home}
		echo "done" >> ${log_file}
	fi
done < $project_file

