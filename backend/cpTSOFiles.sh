dest=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/storage/ProcessedResults/compass_tso500
src=/data/Compass/Analysis/ProcessedResults_NexSeq/OncoPilot/

for fn in $dest/*/*;do 
	cid=$(basename $fn);
	dn=$(dirname $fn);
	pid=$(basename $dn);
	echo -e "$pid/$cid";
	scp biowulf:${src}/${pid}/${cid}/qc/*.tmb ${dest}/${pid}/${cid}/qc/
done


