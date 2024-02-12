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

my $dbh = getDBI();

my $sth_missing_tiers = $dbh->prepare("select c.patient_id,c.case_id,c.path from (select distinct patient_id,case_id from var_samples s where not exists(select * from var_tier_avia a where s.patient_id=a.patient_id and s.case_id=a.case_id)) s, cases c where s.patient_id=c.patient_id and s.case_id=c.case_id");
$sth_missing_tiers->execute();
while (my ($patient_id, $case_id, $path) = $sth_missing_tiers->fetchrow_array) {
  print("processing $patient_id, $case_id in $path\n");
  system("$script_dir/loadVarPatients.pl -i $processed_data_dir/$path -p $patient_id -c $case_id -t tier");
}
$sth_missing_tiers->finish;

$dbh->disconnect();
