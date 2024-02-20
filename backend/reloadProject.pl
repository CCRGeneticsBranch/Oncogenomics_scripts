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
use POSIX;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $project_name;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project name  
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_name  
);

if (!$project_name) {
    die "Project name is missing\n$usage";
}

my $script_dir = dirname(__FILE__);
my $app_path = abs_path($script_dir."/../../..");
my $current_path = abs_path(".");

my $dbh = getDBI();

my @projects = split(/,/, $project_name);
$project_name = join ("','", @projects);
#my $sql = "select distinct c.patient_id,c.case_id,c.path from projects p1, project_cases p2, cases c where p1.id=p2.project_id and p1.name in ('$project_name') and p2.patient_id=c.patient_id and p2.case_id=p2.case_id";
my $sql = "select distinct c.patient_id,c.case_id,c.path from projects p1, project_cases p2, cases c where p1.id=p2.project_id and p1.name in ('$project_name') and p2.patient_id=c.patient_id and p2.case_id=p2.case_id and not exists(select * from var_fusion f where p2.patient_id=f.patient_id and p2.case_id=f.case_id)";
#print($sql."\n");
my $sth_prj = $dbh->prepare($sql);
$sth_prj->execute();
my $current_date = POSIX::strftime('%Y-%m-%d', localtime);
my %case_data = ();
while (my ($patient_id,$case_id,$path) = $sth_prj->fetchrow_array) {
	push @{$case_data{$path}}, "$patient_id/$case_id/successful.txt";	
}
$sth_prj->finish;

while (my ($path, $value) = each (%case_data)) {
	my $fn = "$current_path/${path}.case_list.${current_date}.txt";
	open OUT_FILE, ">$fn";
	print OUT_FILE join("\n", @{$value});
	close(OUT_FILE);
	print("$script_dir/loadVarPatients.pl -i $app_path/storage/ProcessedResults/$path -l $fn\n");
	#system("$script_dir/loadVarPatients.pl -i $app_path/storage/ProcessedResults/$path -l $fn");

} 