#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);

my $processed_data_dir = abs_path($script_dir."/../../../storage/ProcessedResults");

my $patient_id;
my $remove_folder = 0;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Patient ID
  -r            Remove patient folder
  
__EOUSAGE__



GetOptions (
  'p=s' => \$patient_id,
  'r' => \$remove_folder
);

if (!$patient_id) {
    die "Please input patient_id\n$usage";
}


my $dbh = getDBI();

my $sth_var_cases = $dbh->prepare("select distinct path from var_cases where patient_id = '$patient_id'");
$sth_var_cases->execute();
while (my @row = $sth_var_cases->fetchrow_array) {
	my $path = $row[0];
	my $patient_folder = "$processed_data_dir/$path/$patient_id";
	if ($remove_folder) {
		system("rm -rf $patient_folder");
	}
}

$sth_var_cases->finish;

$dbh->do("delete var_samples where patient_id='$patient_id'");
$dbh->do("delete var_cases where patient_id='$patient_id'");
$dbh->do("delete patients where patient_id='$patient_id'");
$dbh->do("delete patient_details where patient_id='$patient_id'");
$dbh->do("delete sample_details s1 where exists(select * from samples s2 where s2.patient_id='$patient_id' and s1.sample_id=s2.sample_id)");
$dbh->do("delete sample_values s1 where exists(select * from samples s2 where s2.patient_id='$patient_id' and s1.sample_id=s2.sample_id)");
$dbh->do("delete samples where patient_id='$patient_id'");
$dbh->do("delete sample_cases where patient_id='$patient_id'");
$dbh->do("delete var_acmg_guide where patient_id='$patient_id'");
$dbh->do("delete var_acmg_guide_details where patient_id='$patient_id'");
$dbh->do("delete var_flag where patient_id='$patient_id'");
$dbh->do("delete var_flag_details where patient_id='$patient_id'");
$dbh->do("delete var_cnv where patient_id='$patient_id'");
$dbh->do("delete var_cnvkit where patient_id='$patient_id'");
$dbh->do("delete var_fusion where patient_id='$patient_id'");
$dbh->do("delete var_tier where patient_id='$patient_id'");
$dbh->do("delete var_tier_avia where patient_id='$patient_id'");
$dbh->do("delete var_qc where patient_id='$patient_id'");
$dbh->do("delete mutation_burden where patient_id='$patient_id'");
$dbh->do("delete neo_antigen where patient_id='$patient_id'");
$dbh->do("delete cases where patient_id='$patient_id'");
$dbh->do("delete project_patients where patient_id='$patient_id'");

$dbh->commit();
$dbh->disconnect();
