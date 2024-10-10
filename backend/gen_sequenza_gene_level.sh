#!/bin/env bash
module load bedtools

#example
# ./gen_sequenza_gene_level.sh /mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/storage/ProcessedResults/compass_exome/CP11246/MD-23-3075/CP11246_T2D_E/sequenza/CP11246_T2D_E/CP11246_T2D_E_segments.txt /mnt/projects/CCR-JK-oncogenomics/static/ref/hg19.genes.coding.bed
seg_file=$1
gene_bed=$2
if [ -f $seg_file ];then
	d=$(dirname $seg_file)
	sample=$(basename $d)
	d=$(dirname $d)	
	seg_bed=`echo $seg_file | sed 's/\.txt$/\.bed/'`
	gene_level_bed=$d/${sample}_genelevel.txt
	if [ ! -f $gene_level_bed ];then
		echo "$gene_level_bed not found. Generate one"
		sed 's/"//g' $seg_file | grep -v '^chromosome' | cut -f1-3,10-13> $seg_bed
		echo -e "#chromosome\tstart.pos\tend.pos\tGene\tCNt\tA\tB" > $gene_level_bed
		#bedtools intersect -a $seg_bed -b $gene_bed -loj | cut -f8,9,10,11,4,5,6 | bedtools groupby -g 1,2,3,5,6,7 -c 8 -o collapse >> $gene_level_bed
		#bedtools intersect -a $seg_bed -b $gene_bed -wo  >> $gene_level_bed
		bedtools intersect -a $seg_bed -b $gene_bed -wo | awk -F'\t' 'BEGIN{OFS=FS}{print $8,$9,$10,$11,$14,$4,$5,$6}' | bedtools sort > $gene_level_bed.tmp
		awk -F'\t' 'BEGIN{OFS=FS}{print $1" "$2" "$3" "$4" "$5,$6,$7,$8}' $gene_level_bed.tmp | sort > $gene_level_bed.tmp.1
		bedtools groupby -i $gene_level_bed.tmp -g 1,2,3,4 -c 5 -o max | awk -F'\t' '{print $1" "$2" "$3" "$4" "$5}' | sort > $gene_level_bed.tmp.2
		join -t$'\t' -1 1 -2 1 $gene_level_bed.tmp.1 $gene_level_bed.tmp.2 | sed 's/ /\t/g' | cut -f1-4,6- | bedtools sort >> $gene_level_bed
		rm $gene_level_bed.tmp $gene_level_bed.tmp.1 $gene_level_bed.tmp.2
		chmod 770 $gene_level_bed
	fi
fi
