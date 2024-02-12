input_file=$1
global_path=$2

d=$( dirname "${BASH_SOURCE[0]}")

echo $d
while read -r line
do
set $line
	patient_id=$1
	new_case_id=$2
	old_case_id=$3
	path=$4
	if [ ! -z $global_path ];then
		path=$global_path
	fi
	echo "${d}/renameCase.pl -p $patient_id -n $new_case_id -o $old_case_id -t $path"
	${d}/renameCase.pl -p $patient_id -n $new_case_id -o $old_case_id -t $path
done < $input_file
