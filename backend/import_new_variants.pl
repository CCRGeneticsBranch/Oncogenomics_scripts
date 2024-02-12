#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Try::Tiny;
use File::Basename;
use DBD::Oracle qw(:ora_types);
use Getopt::Long qw(GetOptions);
use Time::Piece;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $table_name="hg19_annot_oc";
my $has_header = 0;
my $num_commit = -1;
my $script_dir = abs_path(dirname(__FILE__));
my $avia_path = abs_path($script_dir."/../../../site_data/avia/hg19");
my $input_file = $avia_path."/annotation.tsv";
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -i  <string>  Input text file (default: $input_file)
  -t  <string>  Table name (default: $table_name)
  -c            Has header
  -n  <integer> Commit after <n> inserts (default: no early commits)
  
__EOUSAGE__



GetOptions (
  't=s' => \$table_name,
  'i=s' => \$input_file,
  'n=i' => \$num_commit,
  'c' => \$has_header
);

if (!$input_file) {
    die "Some parameters are missing\n$usage";
}

#if file not found, exit
if ( ! -f $input_file) {
	exit 0;
}

my $dbh = getDBI();
my $sid = getDBSID();
my $host = getDBHost();


$SIG{'__WARN__'} = sub {};

#$dbh->do("truncate table $table_name");
print_log("Importing to $input_file on $host ($sid)");
open(IN_FILE, "$input_file") or die "Cannot open file $input_file";

my $num_fields = 0;
my $line = <IN_FILE>;
chomp $line;
my @headers = split(/\t/,$line,-1);
$num_fields = $#headers;

my $sql = "insert into $table_name values(";
for (my $i=0;$i<=$num_fields;$i++) {
	$sql.="?,";
}
chop($sql);
$sql .= ")";
my $sth = $dbh->prepare($sql);

if (!$has_header) {
  seek IN_FILE, 0, 0;
}

my $num_insert = 0;
my $total_insert = 0;
while (<IN_FILE>) {
	chomp;
	my @fields = split(/\t/, $_, -1);
	#print_log($#fields."<==>".$num_fields);
	next if ($#fields < $num_fields);
	for (my $i=0;$i<=$#fields;$i++) {
		$sth->bind_param( $i+1, $fields[$i]);
	}
	try {
		$sth->execute();
		$total_insert++;
	} catch {
		if (/unique constraint/) {
			my $var = "$fields[0]:$fields[1]-$fields[2] $fields[3]>$fields[4]";
			#print_log("The variant $var already exists!");
		}
	};
	
  $num_insert++;
  if ($num_insert == $num_commit) {
      $dbh->commit();
      $num_insert = 0;
  }
}
print_log("Done. ".$total_insert." records inserted");
my $folder = "$avia_path/archives/".localtime->strftime('%Y-%m');
my $arch_file = $folder."/annotation.".localtime->strftime('%Y_%m_%d_%H_%M').".tsv";
system("mkdir -p $folder");
system("chmod 775 $folder");
system("mv $input_file $arch_file");
system("cat $avia_path/failed.tsv >> $avia_path/failed.all.tsv");
close(IN_FILE);
$dbh->commit();
$dbh->disconnect();
print_log("Refreshing var_sample_avia_oc");
system("$script_dir/refreshViews.pl -v");


