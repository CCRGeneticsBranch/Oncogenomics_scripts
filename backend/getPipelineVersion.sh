case_dir=$1
version="NA"
qc_file=`ls -ltr ${case_dir}/qc/*.config*.txt 2> /dev/null | tail -1 | perl -pe 's/.*qc\/(.*)/$1/'`
qc_file=${case_dir}/qc/${qc_file}
#echo $qc_file
if [ -f $qc_file ]; then
	#echo "perl -ne '($v)=$_=~/\"pipeline_version\": \"(.*?)\",/;print $v;' $qc_file"
	version=`perl -ne '($v)=$_=~/\"pipeline_version\": \"(.*?)\",/;chomp $v;print $v;' $qc_file`
fi
if [[ $version == "" ]]; then
	version=`grep Pipeline -A1 $qc_file | tail -1 | cut -d':' -f2 | tr -d ' '`
	version=v$version
	if [[ $version == "" ]]; then
		version="NA"
	fi
fi
echo $version
