case_dir=$1
version="hg19"
qc_file=`ls -ltr ${case_dir}/qc/*.config*.txt 2> /dev/null | tail -1 | perl -pe 's/.*qc\/(.*)/$1/'`
qc_file=${case_dir}/qc/${qc_file}
#echo $qc_file
if [ -f $qc_file ]; then
	#echo "perl -ne '($v)=$_=~/\"pipeline_version\": \"(.*?)\",/;print $v;' $qc_file"
	hg38_cnt=`grep 'hg38.fa' $qc_file | wc -l`
	if [[ $hg38_cnt == "1" ]];then
		version="hg38";
	fi
fi
echo $version
