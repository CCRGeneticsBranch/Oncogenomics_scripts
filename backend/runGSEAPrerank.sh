#!/usr/bin/env bash
#SBATCH --partition=norm
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=12:00:00

#module load java
export PATH=/mnt/projects/CCR-JK-oncogenomics/static/bin/jdk-11.0.15/bin:$PATH
GSEA_HOME=/mnt/projects/CCR-JK-oncogenomics/static/bin/GSEA_4.0.3
GMT_HOME=/mnt/projects/CCR-JK-oncogenomics/static/ref/msigdb_v7.5
fn=$1
out=$2
method=$3
genesets=$4

if [ -z $method ];then
	method="weighted"
fi

if [ -z $genesets ];then	
	genesets=( c2.all.v7.5.1.symbols.gmt c6.all.v7.5.1.symbols.gmt CytoSig_Top250.gmt NCI_GeneSet_v33.gmt )
else
	genesets=( $genesets )
fi


dn=$(dirname "$fn")
bn=$(basename "$fn")
for geneset in "${genesets[@]}"
do
	#echo "$GSEA_HOME/gsea-cli.sh GSEAPreranked -rnk $fn -gmx /data/khanlab/projects/hsienchao/ref/$geneset -out ${bn}_weighted_${geneset} -scoring_scheme weighted -plot_top_x 1000 -set_max 1000 -set_min 15"
	rm -rf $out/${bn}_${method}_${geneset}
	bash $GSEA_HOME/gsea-cli.sh GSEAPreranked -rnk $fn -gmx $GMT_HOME/$geneset -out $out/${bn}_${method}_${geneset} -scoring_scheme ${method} -plot_top_x 50 -set_max 1000 -set_min 15
done
#bash $GSEA_HOME/gsea-cli.sh GSEAPreranked -rnk $fn -gmx $geneset1 -out ${fn}_gsea_classic -scoring_scheme classic -plot_top_x 1000 -set_max 1000 -set_min 15