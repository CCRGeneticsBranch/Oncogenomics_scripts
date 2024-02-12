#!/bin/bash
target_project=$1
target_type=$2
target_db=$3
EXPECTED_ARGS=3
E_BADARGS=65
todaysDate=`date "+%Y%m%d"`
if [ $# -ne $EXPECTED_ARGS ]
then
	target_project='all'
	target_type='tier'
	target_db='all'
	echo "Running $0 $target_project $target_type $target_db"
fi
data_home=/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults
script_home=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/scripts/backend
script_home_dev=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/scripts/backend
db_name='production'
db_name_dev='development'
url='https://fr-s-bsg-onc-d.ncifcrf.gov/clinomics/public'
url_dev='https://fr-s-bsg-onc-d.ncifcrf.gov/clinomics_dev/public'
# projects = (
# "processed_DATA":"biowulf2.nih.gov:/data/khanlab/projects/processed_DATA/" 
# "cmpc":"biowulf2.nih.gov:/data/Clinomics/Analysis/CMPC/"
#  "nbl":"biowulf2.nih.gov:/data/khanlab/projects/NBL/"
#   "guha":"biowulf2.nih.gov:/data/GuhaData/"
#    "alex":"biowulf2.nih.gov:/data/AlexanderP3/Alex/"
#     "collobaration":"biowulf2.nih.gov:/data/khanlab2/collobaration_DATA/" 
#     "toronto":"biowulf2.nih.gov:/data/AlexanderP3/batch_11/");
for project in 'clinomics' 'processed_DATA' 'kuehl' 'Acc_19'
do
	if [ "$target_project" == "all" ] || [ "$target_project" == "$project" ]
	then 
		project_home=${data_home}/${project}
		date=`date +"%Y%m%d"`;
		prefix=${data_home}/update_list/${project}_tier_${date}
		
		log_file=${prefix}.log
		echo "writing to log_file $log_file"
		date >> ${log_file}
		echo "[ INFO ] Finding last ${project}_db_*txt file for update_list" >>${log_file}
		update_list=`ls ${data_home}/update_list/${project}_db_${date1}*txt |grep -ve sync -ve newList|tail -n1`
		# update_list='/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults/update_list/Acc_19_db_20190919-112044.txt';
		echo "[ INFO ] Processing project: $project " >> ${log_file}
		echo "[ INFO ] Using ${update_list}  " >>${log_file}
		if [ "$target_db" == "all" ] || [ "$target_db" == "prod" ]
		then
				echo "[ INFO ] Updating $db_name" >>$log_file
				echo "${script_home}/loadVarPatients.pl -i ${project_home} -t tier -l ${update_list} -d ${db_name} -u ${url}" >> $log_file
				LC_ALL="en_US.utf8" ${script_home}/loadVarPatients.pl -i ${project_home} -t tier -l ${update_list} -d ${db_name} -u ${url} 2>&1 1>>${log_file}
		fi
		if [ "$target_db" == "all" ] || [ "$target_db" == "dev" ]
		then
				echo "[ INFO ] Updating $db_name_dev" >>$log_file
				echo "${script_home_dev}/loadVarPatients.pl -i ${project_home} -t tier -l ${update_list} -d ${db_name_dev} -u ${url_dev} " >> ${log_file}
				LC_ALL="en_US.utf8" ${script_home_dev}/loadVarPatients.pl -i ${project_home} -t tier -l ${update_list} -d ${db_name_dev} -u ${url_dev} 2>&1 1>>${log_file}
		fi

		echo "Done Tiering ${project} at " `date` >> ${log_file}
		echo "==================" >> ${log_file}
	fi
done
