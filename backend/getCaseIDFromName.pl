#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use JSON;
use Data::Dumper;

my $in_file;
my $out_file;
my $targetDir= '/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults';

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:
	-i <string> input file (two columns: patient_id and case_name)
	-o <string> output file (five columns: patient_id, case_name, case_id, pipeline_version, path)

  
__EOUSAGE__



GetOptions (
  'i=s' => \$in_file,
  'o=s' => \$out_file
);

if (!$in_file || !$out_file) {
	die "no input or output file name\n$usage";
}

my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);

my $sth_case = $dbh->prepare("select distinct c.case_id,c.path from cases c where c.patient_id = ? and c.case_name= ?");

open (IN_FILE,"<$in_file") or die "cannot open file $in_file\n";
open (OUT_FILE, ">$out_file") or die "cannot open file $out_file\n";

while (<IN_FILE>){
	chomp;
	my ($patient,$case_name)=split("\t");
	$sth_case->execute($patient,$case_name);
	
	while (my ($case_id, $path) = $sth_case->fetchrow_array) {
		chomp $path;
		if (!$path) {print "Path not exists in $_"; next;}
		my $other = `ls -ltr $targetDir/$path/$patient/$case_id/qc/$patient*config*.txt |tail -n1`;
		if ($other=~/\s(\S+)$/){
			$other = $1;
		}
		chomp $other;
		if (-e $other){
			my $json = decode_json(`cat $other` );
			if (exists $json->{'pipeline_version'}){
				print OUT_FILE join ("\t",$patient,$case_id,$case_name,$json->{'pipeline_version'})."\n";
			}else{
				die "missing\n";
				print OUT_FILE join ("\t",$patient,$case_id,$case_name,$json->{'pipeline_version'})."\n";
			}
		}else{
			print OUT_FILE join ("\t",$patient,$case_id,$case_name,'NA',$path)."\n";
		}
	}
	my $rows = $sth_case->rows;
	if ($rows == 0) {
		print "no results for case: $patient ==> $case_name\n";
	}
}

close(IN_FILE);
close(OUT_FILE);
$sth_case->finish;

$dbh->disconnect();

