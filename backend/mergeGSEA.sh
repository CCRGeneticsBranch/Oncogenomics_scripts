#!/bin/bash

script_file=`realpath $0`
script_home=`dirname $script_file`

export R_LIBS=/mnt/nasapps/development/R/r_libs/4.0.2/
export PATH=/mnt/nasapps/development/R/4.0.2/bin/:$PATH
d=$1
rm -f $d/gsea*.txt
genesets=( NCI c2 c6 CytoSig )
for geneset in "${genesets[@]}"
do
	for fn in $d/*_weighted_${geneset}*/*/gsea_report_for*.xls;do
		bn=$(basename $fn);
		echo $fn | perl -ne 'm/.*\/(.*)_weighted_.*/;print "${1}\t$_"' >> $d/gsea_${geneset}_meta_weighted.txt;
	done
	Rscript $script_home/mergeGSEAwithFDR.R $d/gsea_${geneset}_meta_weighted.txt $d/GSEA_weighted_${geneset}

done
