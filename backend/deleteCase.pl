#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
use Time::Piece;
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);

my $processed_data_dir = abs_path($script_dir."/../../../storage/ProcessedResults");
my $bam_dir = abs_path($script_dir."/../../../storage/bams");
my $patient_id;
my $case_id;
my $path = "processed_DATA";
my $remove_folder = 0;
my $remove_bam = 0;
my $label_failed = 0;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Patient ID
  -c  <string>  Case ID
  -t  <string>  Path (default: $path)
  -r            Remove case folder
  -b            Remove bam folder
  -f            Label case failed
  
__EOUSAGE__



GetOptions (
  'p=s' => \$patient_id,
  'c=s' => \$case_id,
  't=s' => \$path,
  'r' => \$remove_folder,
  'b' => \$remove_bam,
  'f' => \$label_failed
);

if (!$patient_id) {
    die "Please input patient_id\n$usage";
}

if (!$case_id) {
    die "Please input case_id\n$usage";
}



my $dbh = getDBI();

my $sth_var_cases = $dbh->prepare("select distinct path, status from cases where patient_id = '$patient_id' and case_id='$case_id' and path='$path'");
$sth_var_cases->execute();
my $found = 0;
if (my @row = $sth_var_cases->fetchrow_array) {
  $found = 1;
}
$sth_var_cases->finish;
#if ($found) {
  print_log("deleting DB $patient_id, $case_id, $path");
  $dbh->do("delete var_samples where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_type where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_fusion where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_qc where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_qci_annotation where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_qci_summary where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete mutation_burden where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete neo_antigen where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete mixcr_summary where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete mixcr where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_cnv where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_cnvkit where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_tier where patient_id='$patient_id' and case_id='$case_id'");
  $dbh->do("delete var_tier_avia where patient_id='$patient_id' and case_id='$case_id'");  
#}

my $case_folder = "$processed_data_dir/$path/$patient_id/$case_id";
if ($case_id eq "EmptyFolder") {
  $case_folder = "$processed_data_dir/$path/$patient_id";
}
if ($remove_folder) {
    system("rm -rf $case_folder");
}
if ($remove_bam) {
    system("rm -rf $bam_dir/$path/$patient_id/$case_id");
}

#$dbh->do("delete sample_cases where patient_id='$patient_id' and case_id='$case_id'");
if ($label_failed) {
  if ($found) {
    $dbh->do("update processed_cases set status='failed', updated_at=CURRENT_TIMESTAMP where patient_id='$patient_id' and case_id='$case_id'");
    print_log("update processed_cases set status='failed', updated_at=CURRENT_TIMESTAMP where patient_id='$patient_id' and case_id='$case_id'");
  } 
} else {
    $dbh->do("delete processed_cases where patient_id='$patient_id' and case_id='$case_id'");
    print_log("delete processed_cases where patient_id='$patient_id' and case_id='$case_id'");  
}

$dbh->commit();
$dbh->disconnect();

#system("$script_dir/refreshViews.pl -p");
