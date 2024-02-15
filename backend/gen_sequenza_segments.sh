#!/bin/env bash
module load bedtools
seg_file=$1
gene_bed=$2
if [ -f $seg ];then
	seg_bed=`echo $seg_file | sed 's/\.txt$/\.bed/'`
	seg_gene_bed=`echo $seg_file | sed 's/\.txt$/\.genes\.bed/'`
	grep -v '^chromosome' $seg_file > $seg_bed
	bedtools intersect -a $seg_bed -b $gene_bed -loj | cut -f1-13,17 | bedtools groupby -g 1,2,3,4,5,6,7,8,9,10,11,12,13 -c 14 -o collapse > $seg_gene_bed
fi
