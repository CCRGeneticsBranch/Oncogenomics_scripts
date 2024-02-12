in=$1
bn="${in%.*}"
dn=`dirname $in`
script_file=`realpath $0`
script_home=`dirname $script_file`
reconCNV_home=`realpath ${script_home}/../../bin/reconCNV`

if [ ! -f ${bn}.html ];then
	source /var/www/html/miniconda3/etc/profile.d/conda.sh 
	conda activate reconCNV
	cleaned_cnr=${bn}.nochrM_Y.cnr
	grep -v '^chrM' $in | grep -v '^chrY' > ${cleaned_cnr}
	python ${reconCNV_home}/reconCNV.py -r ${cleaned_cnr} -g ${cleaned_cnr} -x ${reconCNV_home}/data/hg19_genome_length_chr.txt -a ${reconCNV_home}/data/hg19_COSMIC_genes_model_chr.txt -s ${bn}.cns -c ${reconCNV_home}/config.json -o ${bn}.html -d $dn
	chrs=()
	for chr in {1..22};do chrs+=("chr$chr");done
	chrs+=('chrX')
	for chr in "${chrs[@]}";do
		chr_cnr=${bn}.${chr}.cnr
		chr_cns=${bn}.${chr}.cns
		chr_len=${reconCNV_home}/data/hg19_genome_length_${chr}.txt
		
		genome_len=${reconCNV_home}/data/hg19_genome_length_chr.txt

		awk -v chr="$chr" '$1==chr || $1=="chromosome"' $in > ${chr_cnr}
		awk -v chr="$chr" '$1==chr || $1=="chromosome"' ${bn}.cns > ${chr_cns}
		awk -v chr="$chr" '$1==chr || $1=="chromosome"' ${genome_len} > ${chr_len}
		#echo "python ${reconCNV_home}/reconCNV.py -r ${chr_cnr} -g ${chr_cnr} -x ${reconCNV_home}/data/hg19_genome_length_chr.txt -a ${chr_len} -s ${chr_cns} -c ${reconCNV_home}/config.json -o ${bn}.${chr}.html -d $dn"
		python ${reconCNV_home}/reconCNV.py -r ${chr_cnr} -g ${chr_cnr} -x ${chr_len} -a ${reconCNV_home}/data/hg19_COSMIC_genes_model_chr.txt -s ${chr_cns} -c ${reconCNV_home}/config.json -o ${bn}.${chr}.html -d $dn
		#python ${reconCNV_home}/reconCNV.py -r ${cleaned_cnr} -g ${cleaned_cnr} -x ${reconCNV_home}/data/hg19_genome_length_chr.txt -a ${reconCNV_home}/data/hg19_COSMIC_genes_model_chr.txt -s ${bn}.cns -c ${reconCNV_home}/config.json -o ${bn}.html -d $dn
	done
fi