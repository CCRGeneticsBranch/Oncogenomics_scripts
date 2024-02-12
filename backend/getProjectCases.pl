#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Try::Tiny;
use MIME::Lite; 
use JSON;
use Data::Dumper;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $project_name;
my $patient_id_mapping_file;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project name
  -m  <string>  patient_id mapping file
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_name,
  'm=s' => \$patient_id_mapping_file
);

if (!$project_name) {
    die "Project name is missing\n$usage";
}

my %patient_id_mappings = ();
if ($patient_id_mapping_file) {
	open (INFILE, "$patient_id_mapping_file") or return;
	while(<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields != 1);
		$patient_id_mappings{$fields[0]} = $fields[1];
	}
	close(INFILE);
}

my $script_dir = dirname(__FILE__);

my $dbh = getDBI();

my @projects = split(/,/, $project_name);
$project_name = join ("','", @projects);
my $sql = "select distinct c.patient_id,c.case_id,c.patient_id as newpatient,c.case_id as newcase,c.path from projects p1, project_cases p2, cases c where p1.id=p2.project_id and p1.name in ('$project_name') and p2.patient_id=c.patient_id and p2.case_id=p2.case_id order by newpatient";
if (!$patient_id_mapping_file) {
	$sql = "select distinct c.patient_id,c.case_id,c.path from projects p1, project_cases p2, cases c where p1.id=p2.project_id and p1.name in ('$project_name') and p2.patient_id=c.patient_id and p2.case_id=p2.case_id order by patient_id";
}
#print($sql."\n");
my $sth_prj = $dbh->prepare($sql);
$sth_prj->execute();
while (my @row = $sth_prj->fetchrow_array) {
	if (exists $patient_id_mappings{$row[0]}) {
		$row[2] = $patient_id_mappings{$row[0]};
	}
	print join("\t", @row)."\n";	
}
$sth_prj->finish;