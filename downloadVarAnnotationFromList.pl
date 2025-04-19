#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
use Data::Dumper;
use MIME::Lite;
require(dirname(abs_path($0))."/lib/Onco.pm");

my $in_file;
my $url = getConfig("URL");
my $token = getConfig("TOKEN");
my $project_name = "";
my $include_pub=0;

my $script_dir = abs_path(dirname(__FILE__));
my $app_path = abs_path($script_dir."/../..");
my $out_dir = "$app_path/storage/project_data";
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

options:

  -i  <string> Input file
  -o  <string> Output directory (default: $out_dir)
  
__EOUSAGE__



GetOptions (
  'i=s' => \$in_file,
  'o=s' => \$out_dir
);
my $start = time;
if (!$in_file) {
    die "Input file missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

open(IN_FILE, "$in_file") or die "Cannot open file $in_file";
<IN_FILE>;
while(<IN_FILE>) {
	chomp;
	my @fields=split(/\t/);
	my $patient_id=$fields[0];
	my $case_id=$fields[1];
	next if (!$patient_id || !$case_id);
	my @types = ();
	my $sql = "select distinct type from var_samples where patient_id='$patient_id' and case_id='$case_id' and type <> 'rnaseq' and type <> 'hotspot'";
	my $sth = $dbh->prepare($sql);
	$sth->execute();
	while (my @row = $sth->fetchrow_array) {
		push @types,$row[0];
	}
	$sth->finish();
	$sql = "select project_id from project_cases where patient_id='$patient_id' and case_id='$case_id'";
	my $sth_project = $dbh->prepare($sql);
	$sth_project->execute();
	my $project_id;
	if (my @row = $sth_project->fetchrow_array) {
		$project_id = $row[0];
	}
	$sth_project->finish();
	foreach my $type(@types) {
		my $cmd = "curl $url/downloadVariantsGet/$token/$project_id/$patient_id/$case_id/$type > $out_dir/$patient_id.$case_id.$type.tsv";
		print("$cmd\n");
		system($cmd);
  }
}
close(IN_FILE);


$dbh->disconnect();
my $total_duration = time - $start;
print "total time: $total_duration s\n";

