cript_file=`realpath $0`
script_path=`dirname $script_file`
data_home=`realpath ${script_path}/../../../storage/ProcessedResults`
script_lib_home=`realpath ${script_path}/../lib`

anno_file=`realpath ${script_path}/../../ref/RSEM/annotation_ENSEMBL_gene_38_SortByID.txt`
for tpm_file in $data_home/tcga_data/*/*/*/TPM_ENS/*.gene.TPM.txt;do
	#echo $tpm_file
	d=$(dirname $(dirname $tpm_file))
	sample_id=$(basename $d)
	count_file=$d/TPM_ENS/${sample_id}.gene.fc.txt
	mkdir -p $d/RSEM_ENS
	out_file=$d/RSEM_ENS/${sample_id}.rsem_ENS.genes.results
	tmp_file=${out_file}.tmp
	join -t $'\t' -1 1 -2 5 <(sed 's/"//g' $count_file|grep -v gene) <(grep -v GeneID $anno_file) | awk -F'\t' 'OFS="\t"{print $7,$1,$8,$8,$2}' | sort -k1,1 > $tmp_file
	#perl -ane '$tpm{$F[3]}=$F[4] if(!$tpm{$F[3]} || $F[4]>$tpm{$F[3]}); END{foreach $gene(sort keys %tpm){print "$gene\t$tpm{$gene}\n"}}' $tpm_file
	echo -e "symbol\tgene_id\tlength\teffective_length\texpected_count\tTPM\tFPKM" > $out_file
	join -t $'\t' -1 1 -2 1 <(grep -v Start $tpm_file|perl -ane '$tpm{$F[3]}=$F[4] if(!$tpm{$F[3]} || $F[4]>$tpm{$F[3]}); END{foreach $gene(sort keys %tpm){print "$gene\t$tpm{$gene}\n"}}'|sort -k1,1) $tmp_file | awk -F'\t' 'OFS="\t"{print $1,$3,$4,$5,$6,$2,"."}' >> $out_file
	wc -l $out_file
	rm $tmp_file
done
