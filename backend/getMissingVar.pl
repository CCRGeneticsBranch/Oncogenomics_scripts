#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;

my $file_name;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -o  <string>  Output file name
  
__EOUSAGE__



GetOptions (
  'o=s' => \$file_name
);

if (!$file_name) {
	die "Please input output file name\n$usage";
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

my $sth_var = $dbh->prepare("select distinct chromosome, start_pos, end_pos, ref, alt from var_samples a where not exists (select * from hg19_annot\@pub_lnk v where SUBSTR(a.chromosome,4) = v.chr and a.start_pos=query_start and a.end_pos=query_end and a.ref=allele1 and a.alt=allele2) and a.chromosome not like 'chrUn%' and a.chromosome not like '%random'");

$sth_var->execute();

open (FILE, ">$file_name") or die "open $file_name error";
while (my ($chr, $start_pos, $end_pos, $ref, $alt) = $sth_var->fetchrow_array) {
	if ( $chr =~ /chr(.*)/ ) {
		$chr = $1;
		print FILE join("\t", $chr, $start_pos, $end_pos, $ref, $alt)."\n";
	} 	
}
close(FILE);
$sth_var->finish;

$dbh->disconnect();
