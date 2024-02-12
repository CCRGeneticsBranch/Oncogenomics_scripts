#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;

my $default_case_name = "20160415";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -c  <string>  Default case name (default: $default_case_name)
  
__EOUSAGE__



GetOptions (
  'c=s' => \$default_case_name
);

my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);

my $sth_read_cases = $dbh->prepare("select patient_id, case_id from cases");
my $sth_var_samples = $dbh->prepare("select distinct patient_id, case_id, sample_id from var_samples");
my $sth_sample_cases = $dbh->prepare("select sample_id, patient_id, case_name from sample_cases");
my $sth_write_cases = $dbh->prepare("update cases set case_name=? where case_id=? and patient_id=?");
my $sth_write_var_cases = $dbh->prepare("update var_cases set case_name=? where case_id=? and patient_id=?");
my %var_cases = ();
my %var_samples = ();
my %sample_cases = ();
my %case_samples = ();

$sth_var_samples->execute();
while (my @row = $sth_var_samples->fetchrow_array) {
	#if (!exists $var_samples{$row[0]}{$row[1]}){
	#	$var_samples{$row[0]}{$row[1]} = ();
	#}
	push @{$var_samples{$row[0]}{$row[1]}}, $row[2];
}
$sth_var_samples->finish;

$sth_sample_cases->execute();
while (my @row = $sth_sample_cases->fetchrow_array) {
	push @{$sample_cases{$row[0]}{$row[1]}}, $row[2];
	push @{$case_samples{$row[2]}{$row[1]}}, $row[0];
}
$sth_sample_cases->finish;

$sth_read_cases->execute();
while (my @row = $sth_read_cases->fetchrow_array) {
	my $patient_id = $row[0];
	my $case_id = $row[1];
	if (!exists $var_samples{$patient_id}{$case_id}) {
		print "$patient_id, $case_id not found in var_samples!\n";
		next;
	}
	my @samples = @{$var_samples{$patient_id}{$case_id}};
	my $total_samples = $#samples + 1;
	my %case_name_cnt = ();
	for my $sample_id (@samples) {
		if (!exists $sample_cases{$sample_id}{$patient_id}) {
			print "$sample_id not found in sample_cases!\n";
			next;
		}
		my @case_names = @{$sample_cases{$sample_id}{$patient_id}};
		for my $case_name (@case_names) {
			$case_name_cnt{$case_name}++;
		}
	}
	#my $case_name_found = $default_case_name;
	my $case_name_found = $case_id;
	while (my ($case_name, $cnt) = each %case_name_cnt) {
		#check if all samples found in this case_name
		if ($case_name_cnt{$case_name} == $total_samples){
			my @samples_in_case_name = @{$case_samples{$case_name}{$patient_id}};
			my $total_samples_in_case_name = $#samples_in_case_name + 1;
			if ($total_samples_in_case_name == $total_samples) {
				$case_name_found = $case_name;
				last;
			}
		}
	}
	#print "patient_id: $patient_id\tcase_id: $case_id\tcase_name: $case_name_found\n";
	$sth_write_cases->execute($case_name_found, $case_id, $patient_id);
	$sth_write_var_cases->execute($case_name_found, $case_id, $patient_id);
}
$sth_read_cases->finish;
$dbh->commit();
$dbh->disconnect();
