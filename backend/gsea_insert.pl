#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use LWP::Simple qw(get);
use Scalar::Util qw(looks_like_number);
use Try::Tiny;
use File::Temp qw/ tempfile tempdir /;
use POSIX;
use Cwd 'abs_path';

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $input_file="";
my $sample_id="";
my $token_id="";
my $patient_id="";
my $case_id="";
my $out_name="";
my $gene_set="";  
my $user_id="";
my $sample_name="";
my $rank_by="";
my $ispublic="";
my $out_path="";
my $normal_project_name="";
my $timestamp="";
my $project_id="";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -i  <string>  Input File name
  -s  <string>  Sample id
  -n  <string>  Sample name
  -t  <string>  Token Id
  -p  <string>  Patient Id
  -c  <string>  Case Id
  -o  <string>  Output folder name
  -g  <string>  gene set used
  -u  <string>  user id 
  -r <string> rank_by 
  -b <string> ispublic 
  -j <string> out_path
  -m <string> normal_project_name
  -a <string> timestamp
  -z <string> project_id  

  
__EOUSAGE__



GetOptions (
  'i=s' => \$input_file,
  's=s' => \$sample_id,
  'n=s' => \$sample_name,
  't=s' => \$token_id,
  'p=s' => \$patient_id,
  'c=s' => \$case_id,
  'o=s' => \$out_name,
  'g=s' => \$gene_set,  
  'u=s' => \$user_id,
  'r=s' => \$rank_by, 
  'b=s' => \$ispublic,
  'j=s' => \$out_path,
  'm=s' => \$normal_project_name,
  'a=s' => \$timestamp, 
  'z=s' => \$project_id,   
);
my $cwd = getcwd();
print "Output ".$out_path;
open FILE, $out_path.'/input_'.$token_id.'.json' or die "Couldn't open file: $!";
my $json = <FILE>;
close FILE;
my $script_dir = abs_path(dirname(__FILE__));
my $app_path = $script_dir."/../..";
my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);
my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );

my $gsea=$dbh->prepare("INSERT INTO GSEA_STATS (USER_ID, INPUT, SAMPLE_ID, TOKEN_ID, PATIENT_ID, CASE_ID, GENE_SET, Output,sample_name,Rank_by,make_public,json,project_normal,date_created,project_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
$gsea->execute($user_id, $input_file,$sample_id,$token_id,$patient_id,$case_id,$gene_set,$out_name,$sample_name,$rank_by,$ispublic,$json,$normal_project_name,$timestamp,$project_id);
$dbh->commit();
print "DONE INSERTING\n";