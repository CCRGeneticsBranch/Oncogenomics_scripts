#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $url = getConfig("URL");
my $project_id;
my $type;
my $high_conf_only = 0;
my $out_file;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project ID
  -o  <string>  Output file
  -c            High confident only 

Example:
  ./downloadProjectNeoAntigen.pl -p 22114 -o Gilbert_neoantigen_high_conf.txt -c 
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  'o=s' => \$out_file,
  'c' => \$high_conf_only
);

if (!$project_id) {
    die "Please input project_id\n$usage";
}

if (!$out_file) {
    die "Please input out_file\n$usage";
}


my $script_dir = dirname(__FILE__);

my $dbh = getDBI();

my $sql = "select distinct sample_id,patient_id,case_id from neo_antigen s where exists(select * from project_samples p where s.sample_id=p.sample_id and project_id=$project_id) order by patient_id,case_id,sample_id";
print "$sql\n";
my $sth_samples = $dbh->prepare($sql);
$sth_samples->execute();
my $high_conf_only_str = "false";
if ($high_conf_only) {
  $high_conf_only_str = "true";
}
my $first = 1;
my $tmp_file = "download.tmp";
while (my ($sample_id, $patient_id, $case_id) = $sth_samples->fetchrow_array) {
  my $cmd = "curl -X POST -F project_id=$project_id -F patient_id=$patient_id -F case_id=$case_id -F sample_id=$sample_id -F high_conf_only=$high_conf_only_str $url/api/getAntigenData";
  print "Running $cmd\n";
  system("$cmd > $tmp_file");
  my $success = 0;
  my $header_elem = readpipe("head -n 1 $tmp_file | cut -f1");
  chomp $header_elem;
  print "$header_elem\n";
  if ( $header_elem eq "patient_id") {
    print "curl sucessful\n";
    $success = 1;
  } else {
    print "curl failed\n";
  }
  if ($success) {
    if ($first) {
      system("grep . $tmp_file > $out_file");
      $first = 0;
    } else {
      system("grep -v '^patient_id' $tmp_file >> $out_file");
    }
    system("rm $tmp_file");
  }
}
$sth_samples->finish;
$dbh->disconnect();

#/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_pub/app/storage/ProcessedResults/processed_DATA$ for fn in Sonde*;do /mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_pub/app/scripts/backend/deleteCase.pl -p $fn -c 20171011 -r;done
#system("$script_dir/refreshViews.pl -p");
