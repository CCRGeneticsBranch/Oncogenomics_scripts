script_file=`realpath $0`
script_path=`dirname $script_file`
data_home=`realpath ${script_path}/../../../storage/ProcessedResults`
script_lib_home=`realpath ${script_path}/../lib`
export R_LIBS=`php ${script_lib_home}/getSiteConfig.php R_LIB`
R_path==`php ${script_lib_home}/getSiteConfig.php R_PATH` 

script_file=$script_path/convertGTEXToRSEM.R
for tpm_file in $data_home/GTEX/*/*/*/TPM_ENS/*.gene.TPM.txt;do
	#echo $tpm_file
	d=$(dirname $(dirname $tpm_file))
	sample_id=$(basename $d)
	count_file=$d/TPM_ENS/${sample_id}.gene.fc.RDS
	mkdir -p $d/RSEM_ENS
	out_file=$d/RSEM_ENS/${sample_id}.rsem_ENS.genes.results	
	${R_path}/Rscript $script_file $count_file $tpm_file $out_file
	wc -l $out_file
done
