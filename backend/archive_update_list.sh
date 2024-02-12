 
data_dir=/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults 
current_date=`date +"%b-%Y"`
for f in ${data_dir}/update_list/*;do
	if [ ! -d "$f" ];then
		date_of_file=`date -r $f +"%b-%Y"`
		if [[ "${current_date}" != "${date_of_file}" ]];then
			mkdir -p ${data_dir}/update_list/${date_of_file}
			mv $f ${data_dir}/update_list/${date_of_file}/
		fi
	fi
done	
