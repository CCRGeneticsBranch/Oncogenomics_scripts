input_file=$1
global_path=$2

d=$( dirname "${BASH_SOURCE[0]}")

echo $d
while read -r line
do
set $line
	patient_id=$1
	case_id=$2
	path=$3
	if [ ! -z $global_path ];then
		path=$global_path
	fi
	echo "${d}/deleteCase.pl -p $patient_id -c $case_id -t $path -r -b"
	${d}/deleteCase.pl -p $patient_id -c $case_id -t $path -r -b
done < $input_file
