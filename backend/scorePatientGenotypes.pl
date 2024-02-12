#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Time::Piece;
use Time::Seconds;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);
my $app_dir=abs_path($script_dir."/../../..");

my $patient_id;
my $replace=0;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  patient ID
  -r            replace old data
  
__EOUSAGE__



GetOptions (
  'p=s' => \$patient_id,
  'r' => \$replace
);

if (!$patient_id) {
	print "$usage\n";
	exit(0);
}

my $dbh = getDBI();
my $cmd = "";

my $sth_gt = $dbh->prepare("select patient_id from patient_genotyping where patient_id='$patient_id'");
$sth_gt->execute();
if ($sth_gt->fetchrow_array) {
	if (!$replace) {
		print "patient $patient_id already exists!\n";
		$sth_gt->finish;
		$dbh->disconnect();
		exit(0);
	} else {
		$dbh->do("delete patient_genotyping where patient_id = '$patient_id'");
	}
}
$sth_gt->finish;
my $sql = "select distinct path,sample_id,sample_name,case_id from processed_sample_cases where patient_id='$patient_id' order by sample_id";
my $sth_samples = $dbh->prepare($sql);
$sth_samples->execute();
my %files = ();
while (my ($path, $sample_id, $sample_name, $case_id) = $sth_samples->fetchrow_array) {
	my $file = "$app_dir/storage/ProcessedResults/$path/$patient_id/$case_id/$sample_id/qc/$sample_id.star.gt";
	if ( -e $file ) {		
		$files{$sample_name}{$case_id} = $file;
		next;
	}
	$file = "$app_dir/storage/ProcessedResults/$path/$patient_id/$case_id/$sample_name/qc/$sample_name.star.gt";
	if ( -e $file ) {
		$files{$sample_name}{$case_id} = $file;
		next;
	}
	$file = "$app_dir/storage/ProcessedResults/$path/$patient_id/$case_id/$sample_id/qc/$sample_id.bwa.gt";
	if ( -e $file ) {
		$files{$sample_name}{$case_id} = $file;
		next;
	}
	$file = "$app_dir/storage/ProcessedResults/$path/$patient_id/$case_id/$sample_name/qc/$sample_name.bwa.gt";
	if ( -e $file ) {
		$files{$sample_name}{$case_id} = $file;
		next;
	}
	$file = "$app_dir/storage/ProcessedResults/$path/$patient_id/$case_id/$sample_name/qc/$sample_name.gt";
	if ( -e $file ) {
		$files{$sample_name}{$case_id} = $file;
		next;
	}
}
$sth_samples->finish;

my %new_list = ();
foreach my $sample_name (sort keys %files) {
	my @case_keys = sort keys %{$files{$sample_name}};
	foreach my $case_id (@case_keys) {
		my $file = $files{$sample_name}{$case_id};
		if ($#case_keys > 0) {
			$new_list{"$sample_name/$case_id"} = $file;
		} else {
			$new_list{"$sample_name"} = $file;
		}
	}
}

my @sample_list = sort keys %new_list;
my $out_str="Sample\t".join("\t", @sample_list)."\n";

my %sample_pairs = ();
foreach my $sample1 (@sample_list) {
	$out_str=$out_str."$sample1";
	my $file1 = $new_list{$sample1};
	foreach my $sample2 (@sample_list) {
		my $file2 = $new_list{$sample2};
		my $res = 0;
		if ($sample1 eq $sample2) {
			$out_str=$out_str."\t1";
		} else {
			if (exists($sample_pairs{$sample2}{$sample1})) {
				$res = $sample_pairs{$sample2}{$sample1};
			} else {
				$res = `perl $script_dir/scoreGenotypes.pl $file1 $file2`;
			}
			$sample_pairs{$sample1}{$sample2} = $res;
			chomp $res;
			$out_str=$out_str."\t$res";
		}
	}
	$out_str=$out_str."\n";
}
print $out_str;

if ($#sample_list > 0) {
	my $sth_gt_ins = $dbh->prepare("insert into /*+ APPEND */ patient_genotyping values(?,?)");
	$sth_gt_ins->execute($patient_id, $out_str);
}

$dbh->disconnect();

