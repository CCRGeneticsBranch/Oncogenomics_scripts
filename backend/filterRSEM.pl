#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';

my $script_dir = dirname(__FILE__);

my $rsem_file=$ARGV[0];
#my $gene_list_file="${script_dir}/../../storage/data/RSEM_gene_list.txt";
my $gene_list_file="${script_dir}/../../ref/RSEM/gencode.v36lift37.annotation.txt";
my %symbols = ();
open (G_FILE, "$gene_list_file") or die "$gene_list_file not found";
while(<G_FILE>) {
	chomp;
	my @fields = split(/\t/);
	next if ($#fields < 0);
	next if ($fields[0] eq "seqname");
	my $symbol = $fields[7];
	$symbols{$symbol} = '';
}
close(G_FILE);

open (R_FILE, "$rsem_file") or die "$rsem_file not found";
my $header = <R_FILE>;
print $header;
my %rsem_data = ();
while(<R_FILE>) {
	chomp;
	my @fields = split(/\t/);
	next if ($#fields < 6);
	my $gene_id = shift(@fields);
	my ($symbol) = $gene_id =~ /ENSG\d+\.\d+_\d+_(.*)/;
	if (!$symbol) {
		($symbol) = $gene_id =~ /ENSG\d+\.\d+_(.*)/;
	}
	
	#print "$#fields\n";
	if ($symbol) {	
		if (exists $symbols{$symbol}) {
			if (exists $rsem_data{$symbol}) {
				for (my $i=1;$i<=5;$i++) {
					$rsem_data{$symbol}[$i] = ($rsem_data{$symbol}[$i] + $fields[$i])/2;
				}
			} else {
				$rsem_data{$symbol} = \@fields;
			}			
			#print "$symbol\t".join("\t", @fields)."\n";
		} else {
			#print "$gene_id\t".join("\t", @fields)."\n";
		}
	} 
}
my @rsem_symbols = sort keys %rsem_data;
#print $#rsem_symbols."\n";
foreach my $symbol (@rsem_symbols) {
    print "$symbol\t".join("\t", @{$rsem_data{$symbol}})."\n";
}
close(R_FILE);