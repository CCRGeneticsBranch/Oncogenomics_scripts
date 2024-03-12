input_file=$1
type=$2

#generate file: select distinct patient_id,case_id,path from cases c where exists(select * from var_cnvkit k where c.patient_id=k.patient_id and c.case_id=k.case_id) and 
#not exists(select * from var_cnvkit_segment k where c.patient_id=k.patient_id and c.case_id=k.case_id)

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
	path=`realpath ${d}/../../../storage/ProcessedResults/$path`
	echo "${d}/uploadCase.pl -i $path -p $patient_id -c $case_id -t $type"
	${d}/uploadCase.pl -i $path -p $patient_id -c $case_id -t $type
done < $input_file
