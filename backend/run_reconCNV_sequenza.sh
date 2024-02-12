script_file=`realpath $0`
script_home=`dirname $script_file`
reconCNV_home=`realpath ${script_home}/../../bin/reconCNV`
home_dir=`realpath ${script_home}/../../..`
source /var/www/html/miniconda3/etc/profile.d/conda.sh 
conda activate reconCNV

cns=$1
cns_dn=`dirname $cns`
bn=$(basename $cns_dn)
dn=$(dirname $cns_dn)
cnr=$dn/$bn.txt
cleaned_cns=${cns_dn}/$bn.cleaned.cns
cleaned_cnr=${dn}/$bn.cleaned.cnr
out_html=${cns_dn}/${bn}_genome_view.html
echo -e "chromosome\tstart\tend\tGene\tBf\tN.BAF\tsd.BAF\tdepth.ratio\tlog2FC\tsd.ratio\tCNt\tA\tB" > $cleaned_cnr
echo -e "chromosome\tstart\tend\tBf\tN.BAF\tsd.BAF\tdepth.ratio\tlog2FC\tcf\tCNt\tA\tB\tLPP\tGene" > $cleaned_cns

rm ${cns_dn}/*.bed
grep -v '^chrM' $cns | grep -v '^chrY' | sed s/\"//g | grep -v 'chromosome' | awk 'OFS="\t" {$8=log($7)/log(2);$9="NA";print}' > ${cleaned_cns}.bed
module load bedtools
echo "bedtools intersect -a ${cleaned_cns}.bed -b ${home_dir}/public/ref/hg19.genes.coding.bed -wa -wb -loj | cut -f1-13,17 > ${cleaned_cns}.genes.bed"
bedtools intersect -a ${cleaned_cns}.bed -b ${home_dir}/public/ref/hg19.genes.coding.bed -wa -wb -loj | cut -f1-13,17 > ${cleaned_cns}.genes.bed
bedtools merge -i ${cleaned_cns}.genes.bed -c 14 -o collapse -delim "," > ${cleaned_cns}.genes.merged.bed
bedtools intersect -a ${cleaned_cns}.bed -b ${cleaned_cns}.genes.merged.bed -wa -wb -loj | cut -f1-13,17 >> ${cleaned_cns}

grep -v '^chrM' $cnr | grep -v '^chrY' | cut -f1-13 | grep -v 'chromosome' | awk 'OFS="\t" {$9=log($8)/log(2);print}' >> ${cleaned_cnr}

echo "python ${reconCNV_home}/reconCNV.py -r ${cleaned_cnr} -x ${reconCNV_home}/data/hg19_genome_length_chr.txt -a ${reconCNV_home}/data/hg19_COSMIC_genes_model_chr.txt -s ${cleaned_cns} -c ${reconCNV_home}/config_sequenza.json -o ${out_html} -d $cns_dn"
#python ${reconCNV_home}/reconCNV.py -r ${cleaned_cnr} -x ${reconCNV_home}/data/hg19_genome_length_chr.txt -a ${reconCNV_home}/data/hg19_COSMIC_genes_model_chr.txt -s ${cleaned_cns} -g ${cleaned_cnr} -c ${reconCNV_home}/config_sequenza.json -o ${out_html} -d $cns_dn
python ${reconCNV_home}/reconCNV.py -r ${cleaned_cnr} -x ${reconCNV_home}/data/hg19_genome_length_chr.txt -a ${reconCNV_home}/data/hg19_COSMIC_genes_model_chr.txt -s ${cleaned_cns} -c ${reconCNV_home}/config_sequenza.json -o ${out_html} -d $cns_dn


