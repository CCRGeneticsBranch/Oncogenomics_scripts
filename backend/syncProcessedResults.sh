#!/bin/bash
target_project=$1
target_type=$2
target_db=$3
EXPECTED_ARGS=3
E_BADARGS=65
export PATH=/mnt/nasapps/development/perl/5.28.1/bin:$PATH
if [ $# -ne $EXPECTED_ARGS ]
then
	echo "Usage: `basename $0` {target project} {process type: db/tier/bam} {production/development/public}"
	exit $E_BADARGS
fi

export ADMIN_ADDY='chouh@nih.gov';

script_file=`realpath $0`
script_home=`dirname $script_file`
home=`realpath ${script_home}/../../..`
data_home=${home}/storage/ProcessedResults
sync_home=${home}/storage/sync
log_home=${sync_home}/logs/`date +"%Y-%m"`
case_list_home=${sync_home}/case_list/`date +"%Y-%m"`
slurm_log_home=${sync_home}/slurm_log/`date +"%Y-%m"`
mkdir -p $log_home
mkdir -p $case_list_home
mkdir -p $slurm_log_home

log_file=$log_home/`date +"%Y-%m-%d-%H:%M:%S"`.$target_type.log
bam_home=${home}/storage/bams
script_lib_home=`realpath ${script_home}/../lib`
db_name=$target_db
url=`grep '^URL=' ${home}/.env | sed 's/URL=//'`

project_file=$sync_home/project_mapping.txt
echo [`date +"%Y-%m-%d %H:%M:%S"`] "project_file = $project_file, target_type=$target_type, target_db=$target_db";
while IFS=$'\t' read -r -a cols
do
	project=${cols[0]}
	succ_list_path=${cols[1]}
	source_path=${cols[2]}
	project_desc=${cols[3]}
	emails=${cols[4]}
	prefix=`date +"%Y-%m-%d-%H:%M:%S"`_${project}_${target_type}
	if [ "$target_project" == "$project" ] || [ "$target_project" == "all" ]
	then		
		project_home=${data_home}/${project}
		project_bam_home=${bam_home}/${project}
		update_list=""
		#if type is db, then sync update list from biowulf
		if [ "$target_type" == "db" ];then
			update_list=${case_list_home}/${prefix}_caselist.txt
			if [ ! -d ${project_home} ]; then
				mkdir ${project_home}
				chmod 770 ${project_home}
				chgrp ncif-www-onc-grp ${project_home}
			fi
			date >> ${log_file}
			echo [`date +"%Y-%m-%d %H:%M:%S"`] "rsync ${succ_list_path} ${case_list_home}/" >> ${log_file}
			rsync -e 'ssh -q' ${succ_list_path} ${case_list_home}/ 

			if [ -s ${case_list_home}/new_list_${project}.txt ];then
				cut -d' ' -f1 ${case_list_home}/new_list_${project}.txt | awk -F/ '{print $(NF-2)"/"$(NF-1)"/"$(NF)}' > $update_list				
			fi
			if [ -f ${case_list_home}/new_list_${project}.txt ];then
				rm ${case_list_home}/new_list_${project}.txt
			fi
		else
			#if type is tier or bam, then use the last update/sync list			
			if ls  ${case_list_home}/*_${project}_db_caselist.txt 1> /dev/null 2>&1;then
				update_list=`ls -tr ${case_list_home}/*_${project}_db_caselist.txt | tail -n1`
				update_list=`realpath $update_list`
			fi			
		fi

		#only production sync processed data and bams
		if [[ -s ${update_list} && "$target_db" == "production" ]];then
			while IFS='' read -r line || [[ -n "$line" ]]
			do
					pat_id=`echo "$line" | awk -F/ '{print $(NF-2)}'`
					case_id=`echo "$line" | awk -F/ '{print $(NF-1)}'`
					status=`echo "$line" | awk -F/ '{print $(NF)}'`

					folder=${pat_id}/${case_id}
					echo [`date +"%Y-%m-%d %H:%M:%S"`] "$pat_id $case_id $status" >> ${log_file}
					if [[ $status == "successful.txt" ]];then
						
						mkdir -p ${project_home}/${pat_id}
						chmod -f 770 ${project_home}/${pat_id}
						chgrp -f ncif-www-onc-grp ${project_home}/${pat_id}
						#sync data file
						if [ "$target_type" == "db" ];then
							#echo ${pat_id}/${case_id}/${status} >> ${update_list}
							echo [`date +"%Y-%m-%d %H:%M:%S"`] "deleting old case..." >> ${log_file}
							perl ${script_home}/deleteCase.pl -p ${pat_id} -c ${case_id} -t ${project} -r >> ${log_file}
							echo [`date +"%Y-%m-%d %H:%M:%S"`] "syncing ${source_path}${folder} ${project_home}/${pat_id}" >> ${log_file}
							#rsync -tirm --include '*/' --include "*.txt" --exclude "dag*.png" --exclude "fusions.discarded.tsv" --include '*.SJ.out.tab' --include '*.SJ.out.bed.gz' --include '*.SJ.out.bed.gz.tbi' --include '*.star.final.bam.tdf' --include '*.tsv'  --include '*.vcf' --include "*.png" --include '*.pdf' --include "*.gt" --include "*.bwa.loh" --include "*hotspot.depth" --include "*.tmb" --include "*.status" --include "*selfSM" --include 'db/*' --include "*tracking" --include "qc/rnaseqc/*" --include "RSEM*/*" --include 'HLA/*' --include 'NeoAntigen/*' --include 'HLA/*' --include 'MHC_Class_I/*' --include 'sequenza/*' --include 'cnvkit/*' --include 'cnvTSO/*' --include '*fastqc/*' --exclude "TPM_*/" --exclude "log/" --exclude "igv/" --exclude "topha*/" --exclude "fusion/*" --exclude "calls/" --exclude '*' ${source_path}${folder} ${project_home}/${pat_id} 2>&1
							rsync -e 'ssh -q' -tirm --include '*/' --include "*.txt" --include "*.html" --exclude "dag*.png" --exclude "fusions.discarded.tsv" --include '*.SJ.out.tab' --include '*.SJ.out.bed.gz' --include '*.SJ.out.bed.gz.tbi' --include '*.star.final.bam.tdf' --include '*.tsv'  --include '*.vcf' --include "*.png" --include '*.pdf' --include "*.gt" --include "*.bwa.loh" --include "*hotspot.depth" --include "*.tmb" --include "*.status" --include "*selfSM" --include 'db/*' --include "*tracking" --include "*exonExpression*" --include "TPM_ENS/*" --include "qc/rnaseqc/*" --include "TPM_UCSC/*" --include "RSEM*/*" --include 'HLA/*' --include 'NeoAntigen/*' --include 'HLA/*' --include 'MHC_Class_I/*' --include 'sequenza/*' --include 'cnvkit/*' --include 'cnvTSO/*' --include '*fastqc/*' --include '*multiqc_data/*' --exclude "TPM_*/" --exclude "log/" --exclude "igv/" --exclude "topha*/" --exclude "fusion/*" --exclude "calls/" --exclude '*' ${source_path}${folder} ${project_home}/${pat_id} >> ${log_file}
							chmod -R -f 770 ${project_home}/${pat_id}/${case_id}
							chgrp -R -f ncif-www-onc-grp ${project_home}/${pat_id}/${case_id}
						fi
						if [ "$target_type" == "bam" ];then
							if [ ! -d ${project_bam_home} ]; then
								mkdir ${project_bam_home}
								chmod -f 770 ${project_bam_home}
								chgrp -f ncif-www-onc-grp ${project_bam_home}
							fi
							if [[ $project == "compass_tso500" ]];then
								rsync -e 'ssh -q' -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*.bam*' --exclude '*' ${source_path}${folder} ${project_bam_home}/${pat_id} >>${log_file}
							else
								#echo "rsync -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*bwa.final.squeeze.bam*' --include '*star.final.squeeze.bam*' --exclude '*' ${source_path}${folder} ${project_home}/${pat_id} >>${log_file} 2>&1"
								echo "rsync rsync -e 'ssh -q' -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*final.squeeze.bam*' --include '*star.fusions.bam*' --exclude '*' ${source_path}${folder} ${project_bam_home}/${pat_id}" >>${log_file}
								rsync -e 'ssh -q' -tirm -L --size-only --remove-source-files --exclude '*/*/*/*/' --include '*/' --include '*final.squeeze.bam*' --include '*star.fusions.bam*' --exclude '*' ${source_path}${folder} ${project_bam_home}/${pat_id} >>${log_file}
							fi
						fi				
					fi								
			done < $update_list
		fi
		
		echo [`date +"%Y-%m-%d %H:%M:%S"`] "update list file: ${update_list}" >> ${log_file}
		if [[ -s ${update_list} && "$target_type" != "bam" ]]; then
			echo [`date +"%Y-%m-%d %H:%M:%S"`] "uploading" >> ${log_file}

			if [ "$target_db" != "public" ]
			then
					if [ "$target_type" == "db" ] 
					then
						echo [`date +"%Y-%m-%d %H:%M:%S"`] "${script_home}/uploadCase.pl -i ${project_home} -o $project_desc $folder-l ${update_list} -d ${db_name} -u ${url}" >> ${log_file}
						LC_ALL="en_US.utf8" perl ${script_home}/uploadCase.pl -i ${project_home} -o $project_desc -l ${update_list} -d ${db_name} -u ${url} 2>&1 1>>${log_file}						
						if [ "$project" != "compass_tso500" ]
						then
							LC_ALL="en_US.utf8" perl ${script_home}/updateVarCases.pl
							#submit this to batch server
							if [ -s ${update_list} ];then
								echo [`date +"%Y-%m-%d %H:%M:%S"`] "sbatch -D ${home}/app/scripts/slurm -o ${slurm_log_home}/${prefix}.preprocessProject.o -e ${slurm_log_home}/${prefix}.preprocessProject.e ${home}/app/scripts/slurm/submitPreprocessProject.sh ${update_list} $emails $url" >> ${log_file}
								sbatch -D ${home}/app/scripts/slurm -o ${slurm_log_home}/${prefix}.preprocessProject.o -e ${slurm_log_home}/${prefix}.preprocessProject.e ${home}/app/scripts/slurm/submitPreprocessProject.sh ${update_list} $emails $url
							fi							
						fi						
					else
						LC_ALL="en_US.utf8" perl ${script_home}/uploadCase.pl -i ${project_home} -l ${update_list} -t $target_type -d ${db_name} -u ${url} 2>&1 1>>${log_file}												
					fi
					echo [`date +"%Y-%m-%d %H:%M:%S"`] "done uploading" >> ${log_file}
			else
					if [ "$target_type" == "db" ];then
						echo [`date +"%Y-%m-%d %H:%M:%S"`] "${script_home}/uploadCase.pl -i ${project_home} -o $project_desc -l ${update_list} -d ${db_name_pub} -u ${url}" >> ${log_file}
						LC_ALL="en_US.utf8" perl ${script_home}/uploadCase.pl -i ${project_home} -o $project_desc -l ${update_list} -d ${db_name_pub} -u ${url} -e chouh@nih.gov 2>&1 1>>${log_file}
						LC_ALL="en_US.utf8" perl ${script_home}/uploadCase.pl -i ${project_home} -o $project_desc -l ${update_list} -d ${db_name_pub} -u ${url} -t tier 2>&1 1>>${log_file}
						LC_ALL="en_US.utf8" perl ${script_home}/updateVarCases.pl
						if [ -s ${update_list} ];then
							echo [`date +"%Y-%m-%d %H:%M:%S"`] "sbatch -D ${home}/app/scripts -o ${slurm_log_home}/${prefix}.preprocessProject.o -e ${slurm_log_home}/${prefix}.preprocessProject.e ${home}/app/scripts/submitPreprocessProject.sh ${update_list} $emails $url"
							sbatch -D ${home}/app/scripts/slurm -o ${slurm_log_home}/${prefix}.preprocessProject.o -e ${slurm_log_home}/${prefix}.preprocessProject.e ${home}/app/scripts/slurm/submitPreprocessProject.sh ${update_list} $emails $url
						fi
					fi
			fi		
		fi
		#find $case_list_home -size 0c -delete
		#chmod -f -R 775 ${project_home}
			
	fi
		
#	fi
done < $project_file

if [ "$target_type" == "db" ];then
	echo [`date +"%Y-%m-%d %H:%M:%S"`] "exporting new variants" >> ${log_file}
	LC_ALL="en_US.utf8" ${script_home}/export_new_variants.pl >> ${log_file}	
	echo [`date +"%Y-%m-%d %H:%M:%S"`] "refreshing views -c -h" >> ${log_file}
	LC_ALL="en_US.utf8" ${script_home}/refreshViews.pl -c -h >> ${log_file}
	echo [`date +"%Y-%m-%d %H:%M:%S"`] "updateing case name/ID" >> ${log_file}
	LC_ALL="en_US.utf8" ${script_home}/updateVarCases.pl >> ${log_file}	
fi
if [ "$target_type" == "bam" ];then
	LC_ALL="en_US.utf8" ${script_home}/checkProcessedResults.pl >> ${log_file}
fi
if [ "$target_type" == "tier" ];then
	echo [`date +"%Y-%m-%d %H:%M:%S"`] "refreshing views -h" >> ${log_file}
	LC_ALL="en_US.utf8" ${script_home}/refreshViews.pl -h >> ${log_file}
fi

echo [`date +"%Y-%m-%d %H:%M:%S"`] "Done syncing. log file: ${log_file}"



