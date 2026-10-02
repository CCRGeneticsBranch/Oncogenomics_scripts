#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';
use Time::Piece;
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = abs_path(dirname(__FILE__));
my $genome = "hg19";

my $usage = <<__EOUSAGE__;

#./export_new_variants.pl -o ../../../site_data/avia/hg19/new_variants.tsv

Usage:

$0 [options]

Options:

  -g            Genome (default: $genome)
  
__EOUSAGE__



GetOptions (
	'g=s' => \$genome
);

my $avia_path = abs_path($script_dir."/../../../avia/$genome");
my $table_name="${genome}_annot_oc";
my $failed_file="$avia_path/failed.all.tsv";
my $out_file = "$avia_path/new_variants.tsv";

my $dbh = getDBI();
my $sid = getDBSID();
my $host = getDBHost();

my %failed_vars = ();
open(FAILED_FILE, "$failed_file") or die "Cannot open file $failed_file";
while(<FAILED_FILE>) {
  chomp;
  my @fields = split(/\t/);
  next if ($#fields < 1);
  $failed_vars{$fields[0].":".$fields[1]} = "";
}

print_log("Exporting to $out_file on $host ($sid)");
my $sql = "select distinct chromosome,start_pos,end_pos,ref,alt from var_samples v, processed_cases c where v.patient_id=c.patient_id and v.case_id=c.case_id and c.genome_version='${genome}' and not exists(select * from $table_name a where v.chromosome=a.chr and v.start_pos=a.query_start and v.end_pos=a.query_end and v.ref=a.allele1 and v.alt=a.allele2) order by chromosome,start_pos,end_pos";
my $sth_novel = $dbh->prepare($sql);
$sth_novel->execute();
open(OUT_FILE, ">$out_file") or die "Cannot open file $out_file";
while (my @row = $sth_novel->fetchrow_array) {
  my $key = $row[0].":".$row[1];
  if (!exists $failed_vars{$key}) {
	 print OUT_FILE join("\t",@row)."\n";
  } 
}
close(OUT_FILE);
system("chmod 770 $out_file");
$dbh->disconnect();
print_log("Done");
