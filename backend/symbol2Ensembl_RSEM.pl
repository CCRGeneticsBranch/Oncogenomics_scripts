#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';

my $script_dir = dirname(__FILE__);

my $rsem_file=$ARGV[0];
my $alias_file="${script_dir}/../../ref/gene_alias_ensembl.tsv";
my $gene_list_file="${script_dir}/../../ref/RSEM/gencode.v36lift37.annotation.txt";
my %symbols = ();
open (G_FILE, "$gene_list_file") or die "$alias_file not found";
<G_FILE>;
while(<G_FILE>) {
	chomp;
	my @fields = split(/\t/);
	next if ($#fields < 0);	
	my $symbol = $fields[7];
	my $ensembl = $fields[4];
	$symbols{$symbol} = $ensembl;	
}
close(G_FILE);
open (G_FILE, "$alias_file") or die "$alias_file not found";
<G_FILE>;
while(<G_FILE>) {
	chomp;
	my @fields = split(/\t/);
	next if ($#fields < 0);	
	my $symbol = $fields[0];
	my $alias = $fields[1];
	my $ensembl = $fields[2];
	$symbols{$symbol} = $ensembl;
	$symbols{$alias} = $ensembl;
}
close(G_FILE);

open (R_FILE, "$rsem_file") or die "$rsem_file not found";
open (OUT_FILE, ">$rsem_file.tmp") or die "$rsem_file.tmp not found";
my $header = <R_FILE>;
print OUT_FILE $header;
my $skip = 0;
while(<R_FILE>) {
	chomp;
	my @fields = split(/\t/);
	next if ($#fields < 6);
	my $gene = shift(@fields);
	if ($gene =~ /^ENSG/) {
		print("this is ENSEMBL file already. Exit.\n");
		$skip = 1;
		last;
	}
	if (exists $symbols{$gene}) {
		print OUT_FILE $symbols{$gene}."\t".join("\t", @fields)."\n";
	}	
}
close(R_FILE);
close(OUT_FILE);
if (!$skip) {
	system("cp $rsem_file $rsem_file.original");
	system("cp $rsem_file.tmp $rsem_file");
}
system("rm $rsem_file.tmp");