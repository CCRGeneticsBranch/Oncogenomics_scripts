#!/bin/bash
#example
#/mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/app/scripts/backend/getIsoformTable.sh TCF3 ENSG00000071564 24421
gene=$1
id=$2
project=$3
home=/mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/storage/project_data
list_file=$home/$project/exp_list-ensembl-gene.tsv
count_file3=$gene.count.v3.ens.tsv
tpm_file3=$gene.tpm.v3.ens.tsv
count_file4=$gene.count.v4.ens.tsv
tpm_file4=$gene.tpm.v4.ens.tsv
cpm_file4=$gene.cpm.v4.ens.tsv
logtpm_file4=$gene.logtpm.v4.ens.tsv
count_file=$gene.count.v3.ucsc.tsv
tpm_file=$gene.tpm.v3.ucsc.tsv
echo -n > $count_file3
echo -n > $tpm_file3
echo -n > $count_file4
echo -n > $tpm_file4
while IFS=$'\t' read -r -a cols
do
	sample=${cols[1]}
	gene_file=${cols[2]}
	diag=${cols[4]}
	iso_file=`echo $gene_file | sed 's/genes/isoforms/'`
	if [ -f $iso_file ];then
		#echo $diag
		grep $gene $iso_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$2"_"$1,$5}' >> $count_file3
		grep $gene $iso_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$2"_"$1,$6}' >> $tpm_file3
	fi
	ucsc_file=`echo $iso_file | sed 's/_ENS/_UCSC/g'`

	if [ -f $ucsc_file ];then
		grep $gene $ucsc_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$2"_"$1,$5}' >> $count_file
		grep $gene $ucsc_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$2"_"$1,$6}' >> $tpm_file
	fi
	total=`grep $gene $iso_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$2"_"$1,$5}' | wc -l`
	if [ $total == "0" ];then
		echo $iso_file
		total=`awk '{sum+=$5} END{print sum}' $iso_file`
		grep $id $iso_file | awk -v total=$total -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$1,$5}' >> $count_file4
		grep $id $iso_file | awk -v total=$total -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$1,$5/total*10^6}' >> $cpm_file4
		grep $id $iso_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$1,$6}' >> $tpm_file4
		grep $id $iso_file | awk -v sample=$sample -v diagnosis="$diag" -F'\t' 'BEGIN {OFS = FS}{print sample,diagnosis,$1,log($6+1)/log(2)}' >> $logtpm_file4
	fi
done < $list_file
