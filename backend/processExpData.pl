#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);

my $input_dir = "/data/khanlab/projects/working_DATA/";
my $output_dir = "/data/khanlab/projects/oncogenomics/data/expression/";
my $show_usage = 0;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

options:
	
	-i  <string>  Input dir  (default: $input_dir)
	-o  <string>  Output dir (default: $output_dir)
	-h            Show usage

__EOUSAGE__



GetOptions (
	'i=s' => \$input_dir,
	'o=s' => \$output_dir
	'h'   => \$show_usage
);

if ($show_usage) {
    print "$usage\n";
    exit 0;
}

my $start = time;

opendir(DIR, $input_dir);
my @dirs = grep(/\_T_/,readdir(DIR));
closedir(DIR);

foreach my $d (@dirs) {
	my ($sample_id)=$d=~/Sample_(.*)/;	

	#Ensembl input file
	my $gene_en_in = $input_dir.$d."/".$d.".Cufflinks_ENSEMBL/genes.fpkm_tracking";
	my $trans_en_in = $input_dir.$d."/".$d.".Cufflinks_ENSEMBL/isoforms.fpkm_tracking";
	my $exon_en_in = $input_dir.$d."/".$d.".Exon_ENSEMBL/$d"."_Exon_Expression.txt";
	
	#UCSC input file
	my $gene_uc_in = $input_dir.$d."/".$d.".Cufflinks_UCSC/genes.fpkm_tracking";
	my $trans_uc_in = $input_dir.$d."/".$d.".Cufflinks_UCSC/isoforms.fpkm_tracking";
	my $exon_uc_in = $input_dir.$d."/".$d.".Exon_UCSC/$d"."_Exon_Expression.txt";
	
	#Ensemble output file
	my $gene_en_out = $output_dir."gene/$sample_id.gene.ensemble.tsv";
	my $trans_en_out = $output_dir."trans/$sample_id.trans.ensemble.tsv";
	my $exon_en_out = $output_dir."exon/$sample_id.exon.ensemble.tsv";

	#UCSC output file
	my $gene_uc_out = $output_dir."gene/$sample_id.gene.ucsc.tsv";
	my $trans_uc_out = $output_dir."trans/$sample_id.trans.ucsc.tsv";
	my $exon_uc_out = $output_dir."exon/$sample_id.exon.ucsc.tsv";

	&processCufflinks($gene_en_in, $gene_en_out, $sample_id);
	&processCufflinks($gene_uc_in, $gene_uc_out, $sample_id);
	&processCufflinks($trans_en_in, $trans_en_out, $sample_id);
	&processCufflinks($trans_uc_in, $trans_uc_out, $sample_id);
	#&insertGene("expr_gene_ensembl", $gene_en, $sample_id, $gene_en_out);
	#&insertTrans("expr_trans", $trans_uc, $sample_id, $trans_uc_out);
	#&insertTrans("expr_trans_ensembl", $trans_en, $sample_id, $trans_en_out);
	#&insertExons("expr_exon", $exon_uc, $sample_id, $exon_uc_out, 3);
	#&insertExons("expr_exon_ensembl", $exon_en, $sample_id, $exon_en_out, 4);
		
}

my $duration = time - $start;
print "Total time: $duration s\n";

sub processCufflinks {
	my ($in_file, $out_file, $sample_id) = @_;
	
	if (-e $out_file) {
		return;
	}	

	open(IN_FILE, $in_file) || die "Cannot open file $in_file";
	open(OUT_FILE, ">$out_file") || die "Cannot open file $out_file";
	my $header_str = <IN_FILE>;
	chomp $header_str;
	my @headers = split(/\t/, $header_str);
	my $tracking_id_idx = -1;
	my $gene_idx = -1;
	my $symbol_idx = -1;
	my $fpkm_idx = -1;
	for (my $i=0; $i<=$#headers; $i++) {
		if ($header eq "tracking_id") {
			$tracking_id_idx = $i;
		}
		if ($header eq "gene_id") {
			$gene_idx = $i;
		}
		if ($header eq "gene_short_name") {
			$symbol_idx = $i;
		}
		if ($header eq "FPKM") {
			$fpkm_idx = $i;
		}
	}

	if ($tracking_id_idx == -1 || $gene_idx == -1 || $symbol_idx == -1 || $fpkm_idx == -1) {
		print "cannot find required columns from file: $gene_en_in\n";
		return;
	}
	print "processing gene level of $sample_id...";
	while(<IN_FILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields < $fpkm_idx);		
		print OUT_FILE $fields[$tracking_id]."\t".$fields[$gene_idx]."\t".$fields[$symbol_idx]."\t".$fields[$fpkm_idx]."\n";
		
	}
	print "done\n";
	close(IN_FILE);
	close(OUT_FILE);
}

sub insertTrans {
	my ($table_name, $file_name, $sample_id, $out_file) = @_;
	#print "inserting trans level of $sample_id...\n";	
	#if (&checkExist($table_name, $sample_id)) {
	#	print "$sample_id already exists in $table_name.";
	#	return;
	#}
	if (!-e $file_name) {
		print "file: $file_name does not exist!";
		return;
	}
	#my $sql_insert = "insert into $table_name values(?,?,?,?)";
	#my $sth_insert = $dbh->prepare($sql_insert);	
	open(IN_FILE, $file_name) || die "Cannot open file $file_name";
	open(OUT_FILE, ">>$out_file") || die "Cannot open file $out_file";
	<IN_FILE>;
	while(<IN_FILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields < 5);
		print OUT_FILE "$sample_id\t".$fields[0]."\t".$fields[1]."\t".$fields[5]."\n";
		#$sth_insert->execute($sample_id, $fields[0], $fields[1], $fields[5]);
	}
	print "done\n";
	close(IN_FILE);
	#$dbh->commit();
}

sub insertExons {
	my ($table_name, $file_name, $sample_id, $out_file, $gene_pos) = @_;
	print "inserting exon level of $sample_id...\n";
	if (&checkExist($table_name, $sample_id)) {
		print "$sample_id already exists in $table_name.\n";
		return;
	}
	if (!-e $file_name) {
		print "file: $file_name does not exist!\n";
		return;
	}
	#my $sql_insert = "insert into $table_name values(?,?,?,?,?,?)";
	#my $sth_insert = $dbh->prepare($sql_insert);	
	open(IN_FILE, $file_name) || die "Cannot open file $file_name";
	open(OUT_FILE, ">>$out_file") || die "Cannot open file $out_file";
	while(<IN_FILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields < 6);
		print OUT_FILE "$sample_id\t".$fields[0]."\t".$fields[1]."\t".$fields[2]."\t".$fields[$gene_pos]."\t".$fields[6]."\n";
		#$sth_insert->execute($sample_id, $fields[0], $fields[1], $fields[2], $fields[4], $fields[6]);
	}
	print "done\n";
	close(IN_FILE);
	#$dbh->commit();
}

sub checkExist {
	return 0;
	my ($table_name, $sample_id) = @_;
	my $sql_check_exists = "select count(*) from $table_name where sample_id=?";
	my $sth_check_exists = $dbh->prepare($sql_check_exists);
	$sth_check_exists->execute($sample_id);
	if (my @row = $sth_check_exists->fetchrow_array) {
		return ($row[0] > 0)
	}
	return 0;
}
