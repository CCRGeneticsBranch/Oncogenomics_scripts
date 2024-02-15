#!/bin/env bash
module load bedtools
seg_file=$1
gene_bed=$2
if [ -f $seg ];then
	seg_bed=`echo $seg_file | sed 's/\.cns$/\.segments\.bed/'`
	seg_gene_bed=`echo $seg_file | sed 's/\.cns$/\.segments\.genes\.bed/'`
	cut -f1,2,3,5,6,7 $seg_file | grep -v '^chromosome' > $seg_bed
	bedtools intersect -a $seg_bed -b $gene_bed -loj | cut -f1-6,10 | bedtools groupby -g 1,2,3,4,5,6 -c 7 -o collapse > $seg_gene_bed
fi
