#!/bin/env bash
module load bedtools
seg_file=$1
gene_bed=$2
type=$3
if [ -f $seg ];then
	if [ "$type" == "1" ];then
		seg_bed=`echo $seg_file | sed 's/\.call\.cns$/\.segments\.bed/'`
		seg_gene_bed=`echo $seg_file | sed 's/\.call\.cns$/\.segments\.genes\.bed/'`
		cut -f1-3,5- $seg_file | grep -v '^chromosome' > $seg_bed
		bedtools intersect -a $seg_bed -b $gene_bed -loj | cut -f1-13,17 | bedtools groupby -g 1,2,3,4,5,6,7,8,9,10,11,12,13 -c 14 -o collapse > $seg_gene_bed
	else		
		seg_bed=`echo $seg_file | sed 's/\.cns$/\.segments\.bed/'`
		seg_gene_bed=`echo $seg_file | sed 's/\.cns$/\.segments\.genes\.bed/'`
		cut -f1,2,3,5,6,7,8 $seg_file | grep -v '^chromosome' > $seg_bed
		bedtools intersect -a $seg_bed -b $gene_bed -loj | cut -f1-7,11 | bedtools groupby -g 1,2,3,4,5,6,7 -c 8 -o collapse > $seg_gene_bed
	fi
fi
