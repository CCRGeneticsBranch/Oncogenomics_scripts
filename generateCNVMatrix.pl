#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/lib/Onco.pm");

my $project_id;
my $type = "sequenza";
my $script_dir = dirname(__FILE__);
my $app_path = abs_path($script_dir."/../..");
my $out_dir = "$app_path/storage/project_data";
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project ID
  -t  <string>  Type [sequenza|cnvkit] default: $type
  -o  <string>  Output dir (default: $out_dir)

Example:
  ./generateCNVMatrix.pl -p 22114 -t cnvkit
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  't=s' => \$type,
  'o=s' => \$out_dir
);

if (!$project_id) {
    die "Please input project_id\n$usage";
}

if (!$type) {
    die "Please input type\n$usage";
}

my $dbh = getDBI();

my $cnv_table = "var_cnv_genes";
my $fn = "cnt";
if ($type eq "cnvkit") {
  $cnv_table = "var_cnvkit_genes";
  $fn = "log2";
}
my $cnt_sql = "select count(*) as cnt from $cnv_table c, project_samples p where c.sample_id=p.sample_id and project_id=$project_id";
my $sth_cnv_cnt = $dbh->prepare($cnt_sql);
$sth_cnv_cnt->execute();
if (my ($cnt) = $sth_cnv_cnt->fetchrow_array) {
  if ($cnt == 0) {
    print("No data in $type!\n");
    $sth_cnv_cnt->finish;
    $dbh->disconnect();
    exit(1);
  }
}
$sth_cnv_cnt->finish;

my $sql = "select distinct c.sample_name,gene,$fn from $cnv_table c, project_samples p where c.sample_id=p.sample_id and project_id=$project_id";
#print "$sql\n";
print "generating CNV matrix for project $project_id\n";
my $sth_cnv = $dbh->prepare($sql);
$sth_cnv->execute();

my %samples = ();
my %genes = ();
my %cnts = ();
while (my ($sample_name,$gene,$cnt) = $sth_cnv->fetchrow_array) {
  if ($gene) {
    $samples{$sample_name} = '';
    $genes{$gene} = '';
    $cnts{$sample_name}{$gene} = $cnt;
  }
}
$sth_cnv->finish;
$dbh->disconnect();
my $out_file = "$out_dir/$project_id/cnv/$project_id.$type.matrix.tsv";
system("mkdir -p $out_dir/$project_id/cnv");
open(OUT_FILE, ">$out_file") or die "cannot open file $out_file";
my @sample_list = sort keys %samples;
foreach my $sample (@sample_list) {
  print OUT_FILE "\t$sample";
}
print OUT_FILE "\n";
foreach my $gene (sort keys %genes) {
  print OUT_FILE $gene;
  foreach my $sample (@sample_list) {
    my $value = "NA";
    if (exists $cnts{$sample}{$gene}) {
      $value = $cnts{$sample}{$gene};
    }
    print OUT_FILE "\t$value";
  }
  print OUT_FILE "\n";
}

