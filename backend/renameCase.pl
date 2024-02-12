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
my $bam_dir = abs_path($script_dir."/../../../storage/bams");
my $patient_id;
my $old_case_id;
my $new_case_id;
my $path = "processed_DATA";
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Patient ID
  -o  <string>  Old Case ID
  -n  <string>  New Case ID
  -t  <string>  Path (default: $path)
  
__EOUSAGE__



GetOptions (
  'p=s' => \$patient_id,
  'o=s' => \$old_case_id,
  'n=s' => \$new_case_id,
  't=s' => \$path
);

if (!$patient_id) {
    die "Please input patient_id\n$usage";
}

if (!$old_case_id) {
    die "Please input old_case_id\n$usage";
}

if (!$new_case_id) {
    die "Please input new_case_id\n$usage";
}

if ( -d "$processed_data_dir/$path/$patient_id/$new_case_id" ) {
  print("directory $processed_data_dir/$path/$patient_id/$new_case_id already exists! Abort.\n");
  exit(0);
}
if ( -d "$bam_dir/$path/$patient_id/$new_case_id" ) {
  print("directory $bam_dir/$path/$patient_id/$new_case_id already exists! Abort.\n");
  exit(0);
}

system("mv $bam_dir/$path/$patient_id/$old_case_id $bam_dir/$path/$patient_id/$new_case_id");
system("mv $processed_data_dir/$path/$patient_id/$old_case_id $processed_data_dir/$path/$patient_id/$new_case_id");
print("$script_dir/deleteCase.pl -p $patient_id -c $old_case_id -t $path\n");
system("$script_dir/deleteCase.pl -p $patient_id -c $old_case_id -t $path");
print("$script_dir/loadVarPatients.pl -p $patient_id -c $new_case_id -i $path\n");
system("$script_dir/loadVarPatients.pl -p $patient_id -c $new_case_id -i $processed_data_dir/$path");
