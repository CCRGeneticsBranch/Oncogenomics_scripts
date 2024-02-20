#!/bin/bash
target_project=$1
target_type=$2
EXPECTED_ARGS=2
E_BADARGS=65
export PATH=/mnt/nasapps/development/perl/5.28.1/bin:$PATH
if [ $# -ne $EXPECTED_ARGS ]
then
	echo "Usage: `basename $0` {target project or all} {process type: all/tier/fusion}"
	exit $E_BADARGS
fi

script_file=`realpath $0`
script_home=`dirname $script_file`
html_home=`realpath ${script_home}/../../../..`
script_home_dev=${html_home}/clinomics_dev/app/scripts/backend
data_home=${script_home}/../../../storage/ProcessedResults
script_lib_home=`realpath ${script_home}/../lib`
url=`php ${script_lib_home}/getSiteConfig.php url`
url_dev=`php ${script_lib_home}/getSiteConfig.php url_dev`

db_name='production'
db_name_dev='development'
url='https://fsabcl-onc01d.ncifcrf.gov/clinomics/public'
url_dev='https://fsabcl-onc01d.ncifcrf.gov/clinomics_dev/public'


project_file=$script_home/project_mapping.txt
echo "project_file = $project_file";
while IFS=$'\t' read -r -a cols
do
	project=${cols[0]}
	succ_list_path=${cols[1]}
	source_path=${cols[2]}
	echo "working on $project ...."
	if [ "$target_project" == "$project" ] || [ "$target_project" == "all" ]
	then
		project_home=${data_home}/${project}
		echo perl ${script_home}/loadVarPatients.pl -i ${project_home} -t $target_type
		LC_ALL="en_US.utf8" perl ${script_home}/loadVarPatients.pl -i ${project_home} -t $target_type
	fi
done < $project_file

echo "Done! at " `date`


