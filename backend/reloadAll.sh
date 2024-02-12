type=$1

script_file=`realpath $0`
script_home=`dirname $script_file`
app_dir=`realpath ${script_home}/../../../`

for d in `cat processed_paths.txt`;do 
	echo "${app_dir}/scripts/backend/loadVarPatients.pl -i ${app_dir}/storage/ProcessedResults/$d -t $type"
	${app_dir}/scripts/backend/loadVarPatients.pl -i ${app_dir}/storage/ProcessedResults/$d -t $type
done
