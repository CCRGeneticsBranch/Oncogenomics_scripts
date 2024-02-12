script_file=`realpath $0`
script_home=`dirname $script_file`
path=$1
out_file="gt.txt"
echo Sample > first_column.txt
for f1 in $path/*/*/qc/*.gt;do
	sample=`basename ${f1} .gt`
	echo $sample >> first_column.txt
	echo $sample >> ${sample}.ratio
	for f2 in $path/*/*/qc/*.gt;do
		perl $script_home/scoreGenotypes.pl $f1 $f2 >>${sample}.ratio
	done
done
paste first_column.txt *.ratio > $out_file
sed -i 's/Sample_//g' $out_file
sed -i 's/.bwa//g' $out_file
sed -i 's/.star//g' $out_file
rm *.ratio
rm first_column.txt

