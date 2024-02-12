#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
use Data::Dumper;
use MIME::Lite;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $project_id;
my $email = "";
my $project_name = "";
my $include_pub=0;

my $script_dir = abs_path(dirname(__FILE__));
my $app_path = abs_path($script_dir."/../../..");
my $data_dir = abs_path($app_path."/storage/ProcessedResults");
my $out_dir = "$app_path/storage/project_data";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

options:

  -p  <string> Project id
  -o  <string> Output directory (default: $out_dir)
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  'o=s' => \$out_dir  
);
my $start = time;
if (!$project_id) {
    die "Project id is missing\n$usage";
}

my $dbh = getDBI();

my $sql_prj = "select name from projects where id=$project_id";
my $sth_prj = $dbh->prepare($sql_prj);
$sth_prj->execute();
if (my @row = $sth_prj->fetchrow_array) {
	$project_name = $row[0];
} else {
	die "project id: $project_id not found\n";
}
$sth_prj->finish();
my $sql = "select distinct c.patient_id,c.case_id,c.path from project_cases p, cases c where p.patient_id=c.patient_id and p.case_id=c.case_id and c.case_id is not null and p.project_id=$project_id";
my $sth = $dbh->prepare($sql);
$sth->execute();
my %data = ();
my $out_zip = "$out_dir/$project_id/$project_id.vcf.zip";
if ( -e $out_zip ) {
	system("rm $out_zip");
}
while (my @row = $sth->fetchrow_array) {
	my $patient_id = $row[0];
	my $case_id = $row[1];
	my $path = $row[2];
	my $vcf = "$data_dir/$path/$patient_id/$case_id/$patient_id.$case_id.vcf.zip";
	#print "$vcf\n";
	#system("rm $vcf");
	if ( ! -e  $vcf ){		
		print "$vcf not found! Making zip file\n";
		my $cmd = "cd $data_dir/$path; zip $patient_id/$case_id/$patient_id.$case_id.vcf.zip $patient_id/$case_id/*/calls/*.snpEff.vcf; cd -";
		print "$cmd\n";
		if ( glob("$data_dir/$path/$patient_id/$case_id/*/calls/*.snpEff.vcf")) {
			system($cmd);
		}
	}
	if (-e  $vcf ){
		system("zip -j $out_zip $vcf");
	} else {
		print "$vcf still not found!\n";
	}
}
$sth->finish();

$dbh->disconnect();

sub formatDir {
    my ($dir) = @_;
    if ($dir !~ /\/$/) {
        $dir = $dir."/";
    }
    return $dir;
}
