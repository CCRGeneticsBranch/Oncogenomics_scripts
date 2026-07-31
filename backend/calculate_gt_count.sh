for fn in /var/www/html/clinomics/storage/ProcessedResults/*/*/*/*/qc/*.gt;do 
	bn=$(basename $fn)
	bn=`echo $bn | sed 's/\.gt$//'`
	wl=`wc -l $fn| cut -d ' ' -f1`;
	echo -e "$bn\t$wl";
done
