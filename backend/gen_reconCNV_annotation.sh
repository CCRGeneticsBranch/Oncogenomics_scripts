gtf=$1
out=$2
#/mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/app/scripts/backend/gen_reconCNV_annotation.sh gencode.v38lift37.annotation.sorted.genename_changed.gtf gencode.v38lift37.annotation.reconCNV.txt
echo -e "chromosome\texonStarts\texonEnds\tname\texon_number\tname2" > $out
awk '$3=="exon"' $gtf | perl -F"\t" -ane '($t,$g,$e)=$F[8]=~/transcript_id "(.*?)".*gene_name "(.*?):.*exon_number (.*?);/;print "$F[0]\t$F[3]\t$F[4]\t$t\t$e\t$g \n"' >> $out
chrs=()
for chr in {1..22};do chrs+=("chr$chr");done
chrs+=('chrX')
for chr in "${chrs[@]}";do
	echo -e "chromosome\texonStarts\texonEnds\tname\texon_number\tname2" > ${chr}.annotation.txt
	awk -v chr="$chr" '$1==chr' $out >> ${chr}.annotation.txt
done