#!/bin/env bash
module load bedtools

#example
# ./gen_sequenza_segments.sh /mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/storage/ProcessedResults/compass_exome/CP11246/MD-23-3075/CP11246_T2D_E/sequenza/CP11246_T2D_E/CP11246_T2D_E_segments.txt /mnt/projects/CCR-JK-oncogenomics/static/ref/hg19.genes.coding.bed
seg_file=$1
gene_bed=$2
if [ -f $seg_file ];then
	d=$(dirname $seg_file)
	sample=$(basename $d)
	d=$(dirname $d)	
	seg_bed=`echo $seg_file | sed 's/\.txt$/\.bed/'`
	seg_gene_bed=$d/$sample.segments.genes.bed
	sed 's/"//g' $seg_file | grep -v '^chromosome' | cut -f1-3,10-13> $seg_bed
	bedtools intersect -a $seg_bed -b $gene_bed -loj | cut -f1-7,11 | bedtools groupby -g 1,2,3,4,5,6,7 -c 8 -o collapse > $seg_gene_bed
	chmod 770 $seg_gene_bed	
fi
