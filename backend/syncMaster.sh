#/bin/bash

# regular master file syncing:
# ./syncMaster.sh
#
# sync specific project to public site:
# ./syncMaster.sh <project name>
#
# e.g.
# ./syncMaster.sh CRUK
#
export PATH=/mnt/nasapps/development/perl/5.28.1/bin:$PATH
script_file=`realpath $0`
script_path=`dirname $script_file`
home=`realpath ${script_path}/../../../..`
script_home_production=$script_path
script_home_dev=${home}/clinomicsd/app/scripts/backend
script_home_public=${home}/clinomics_public/app/scripts/backend
data_home=${script_home_production}/../../metadata
todaysdate=`date "+%Y%m%d-%H%M"`;

master_files=()
flags=()
project_groups=()
no_change="Y"

master_file_mapping=$data_home/master_files.txt
projects=$1

while IFS=$'\t' read -r -a cols
do
	src_file=${cols[0]}
	project_group=${cols[1]}
	file=$(basename $src_file)
	echo -e `date +"%Y-%m-%d %H:%M:%S"` "$src_file\t$project_group\t$file"
	modify_time=""
	if [ -f $data_home/$file ];then
		modify_time=`stat --printf=%y $data_home/$file`
	fi
	if [ -z $projects ];then
		rsync -e 'ssh -q' -aiz ${src_file} $data_home/
		new_modify_time=`stat --printf=%y $data_home/$file`
		[ "$modify_time" =  "$new_modify_time" ] ; modified=$?
		if [ $modified = "1" ];then 
			echo `date +"%Y-%m-%d %H:%M:%S"` "file $file has been changed"
			no_change="N"
		fi
	fi
	master_files[${#master_files[@]}]=$data_home/$file
	flags[${#flags[@]}]=$modified
	project_groups[${#project_groups[@]}]=$project_group

done < $master_file_mapping

file_list=$(IFS=, ; echo "${master_files[*]}")
flag_list=$(IFS=, ; echo "${flags[*]}")
project_group_list=$(IFS=, ; echo "${project_groups[*]}")

if [ -z $projects ];then
	if [[ $no_change = "N" ]];then
		echo `date +"%Y-%m-%d %H:%M:%S"` "Uploading production database..."
		echo `date +"%Y-%m-%d %H:%M:%S"` "$script_home_production/syncMaster.pl -u -n production -i $file_list -m $flag_list -g $project_group_list"
		perl $script_home_production/syncMaster.pl -u -n production -i $file_list -m $flag_list -g $project_group_list
		perl $script_home_production/runDBQuery.pl "select distinct patient_id,case_name from sample_case_mapping order by patient_id" > ${data_home}/case_list.txt
		echo `date +"%Y-%m-%d %H:%M:%S"` "$script_home_production/runDBQuery.pl \"select distinct patient_id,case_name from sample_case_mapping order by patient_id\" > ${data_home}/case_list.txt"
		scp ${data_home}/case_list.txt helix:/data/Clinomics/MasterFiles/	
		echo `date +"%Y-%m-%d %H:%M:%S"` "Uploading development database..."
		echo `date +"%Y-%m-%d %H:%M:%S"` "$script_home_dev/syncMaster.pl -u -n production -i $file_list -m $flag_list -g $project_group_list"		
		perl $script_home_dev/syncMaster.pl -u -n development -i $file_list -m $flag_list -g $project_group_list
	elif [[ $todaysdate =~ 090[0-6] ]]
	then 
		# Run once a day so I know cron is running
		echo `date +"%Y-%m-%d %H:%M:%S"` "-------------------------";
		echo `date +"%Y-%m-%d %H:%M:%S"` "Masters files is not updated @$todaysdate" 
		echo -e `date +"%Y-%m-%d %H:%M:%S"` $msg
		echo `date +"%Y-%m-%d %H:%M:%S"` "-------------------------";
	fi
else
	echo `date +"%Y-%m-%d %H:%M:%S"` "Uploading public database..."
	echo `date +"%Y-%m-%d %H:%M:%S"` "$script_home_public/syncMaster.pl -u -n public -i $file_list -m $flag_list -g $project_group_list -l $projects"
	perl $script_home_public/syncMaster.pl -u -n public -i $file_list -m $flag_list -g $project_group_list -l $projects
fi

