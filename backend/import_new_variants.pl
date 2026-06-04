#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Try::Tiny;
use File::Basename;
use Getopt::Long qw(GetOptions);
use Time::Piece;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");


my $dbh = getDBI();
my $sid = getDBSID();
my $host = getDBHost();


$SIG{'__WARN__'} = sub {};

#$dbh->do("truncate table $table_name");

my $script_dir = abs_path(dirname(__FILE__));

my @genomes = ( "hg19", "hg38" );

my $need_refresh = 0;

foreach my $genome(@genomes) {
	my $table_name = $genome."_annot_oc";
	my $has_header = 0;
	my $num_commit = -1;
	
	my $avia_path = getConfig("AVIA_PATH")."/".$genome;
	my $input_file = $avia_path."/annotation.tsv";

	print_log("Importing $input_file on $host ($sid)");
	if ( ! -f $input_file ) {
		print_log("$input_file not exists. Skip $genome");
		next;
	}
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
	system("chmod 777 $folder");
	system("mv $input_file $arch_file");
	system("cat $avia_path/failed.tsv >> $avia_path/failed.all.tsv");
	close(IN_FILE);
	$need_refresh = 1;
	$dbh->commit();
}
$dbh->disconnect();
if ($need_refresh) {
	print_log("Refreshing var_sample_avia_oc");
	system("$script_dir/refreshViews.pl -v");
}
print_log("Done");


