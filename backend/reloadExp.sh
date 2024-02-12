#!/bin/bash

data_home=/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults
script_home=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/scripts/backend
script_home_dev=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/scripts/backend
project_file=$script_home_dev/project_mapping.txt

while IFS=$'\t' read -r -a cols
do
	project=${cols[0]}
	path=${cols[1]}
	project_home=${data_home}/${project}
	echo "Running: ${script_home}/loadVarPatients.pl -i ${project_home} -t exp -s"
	LC_ALL="en_US.utf8" ${script_home}/loadVarPatients.pl -i ${project_home} -t exp -s
done < $project_file
