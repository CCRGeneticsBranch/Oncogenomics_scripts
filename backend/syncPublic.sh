#app/scripts/backend/syncPublic.sh <project name>

project_name=$1
email=$2
url=https://fsabcl-onc01d.ncifcrf.gov/clinomics_public/public
root_dir=/mnt/projects/CCR-JK-oncogenomics/static/clones
pro_dir=$root_dir/clinomics
pub_dir=$root_dir/clinomics_public
sync_dir=$root_dir/clinomics_public/storage/update_list
suffix=`date +"%Y%m%d-%H%M%S"`

echo "==== step 1: sync master file ===="
echo "command: $pub_dir/app/scripts/backend/syncMaster.sh $project_name"
$pub_dir/app/scripts/backend/syncMaster.sh $project_name

echo "==== step 2: get project cases from internal ===="
echo "command: $pro_dir/app/scripts/backend/getProjectCases.pl -p $project_name > $sync_dir/project_cases/project_cases_$suffix.tsv"
$pro_dir/app/scripts/backend/getProjectCases.pl -p $project_name > $sync_dir/project_cases/project_cases_$suffix.tsv


echo "==== step 3: prepare new list files for sync ===="
rm ${sync_dir}/source_list/new_list_*.txt

while IFS=$'\t' read -r -a cols
do
	patient_id=${cols[0]}
	case_id=${cols[1]}
	path=${cols[2]}
	succ_file=$pro_dir/storage/ProcessedResults/$path/$patient_id/$case_id/successful.txt	
	if [ -f $succ_file ];then
		echo $succ_file
		echo "${sync_dir}/source_list/new_list_${path}.txt"
		echo $succ_file >> ${sync_dir}/source_list/new_list_${path}.txt
	fi
done < $sync_dir/project_cases/project_cases_$suffix.tsv

echo "==== step 4: sync and upload data ===="
echo "command: $pub_dir/app/scripts/backend/syncProcessedResults.sh all db pub"
$pub_dir/app/scripts/backend/syncProcessedResults.sh all db pub

if [ ! -z $email ];then
	echo "==== step 5: send notification email ===="
	echo "command: ./sendEmail.pl -s \"Oncogenomics public project $project_name synced\" -c \"Project $project_name has been synced to public site successfully! \" -e $email"
	./sendEmail.pl -s "Oncogenomics public project $project_name synced" -c "Project $project_name has been synced to public site successfully! " -e $email
	#echo "command: mail -r chouh@nih.gov -s \"Oncogenomics public project $project_name synced\" $email <<< \"Project $project_name has been synced to public site successfully\! \""
	#mail -r chouh@nih.gov -s "Oncogenomics public project $project_name synced" $email <<< "Project $project_name has been synced to public site successfully! "
fi

