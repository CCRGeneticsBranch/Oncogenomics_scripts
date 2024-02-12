#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);

my $url = getConfig("URL")."/api/downloadVariants";
my $project_id;
my $type;
my $high_conf_only = 0;
my $out_file;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project ID
  -t  <string>  Type (germline, somatic, rnaseq, variants)
  -o  <string>  Output file
  -c            High confident variants only 

Example:
  ./downloadProjectVariants.pl -p 22114 -t somatic -o Gilbert_somatic_high_conf.txt -c 
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  't=s' => \$type,
  'o=s' => \$out_file,
  'c' => \$high_conf_only
);

if (!$project_id) {
    die "Please input project_id\n$usage";
}

if (!$type) {
    die "Please input type\n$usage";
}

if (!$out_file) {
    die "Please input out_file\n$usage";
}

my $dbh = getDBI();

my $sql = "select distinct sample_id,patient_id,case_id,exp_type,tissue_cat from var_samples s where type='$type' and exists(select * from project_samples p where s.sample_id=p.sample_id and project_id=$project_id) order by patient_id,case_id,sample_id";
print "$sql\n";
my $sth_samples = $dbh->prepare($sql);
$sth_samples->execute();
my $high_conf_only_str = "false";
if ($high_conf_only) {
  $high_conf_only_str = "true";
}
my $first = 1;
while (my ($sample_id, $patient_id, $case_id, $exp_type, $tissue_cat) = $sth_samples->fetchrow_array) {
  if ($type eq "germline") {
     next if ($tissue_cat ne "normal");
  }
  if ($type eq "somatic") {
     next if ($tissue_cat ne "tumor" && $tissue_cat ne "cellline");
  }
  my $cmd = "curl -F type=$type -F project_id=$project_id -F annotation=avia -F patient_id=$patient_id -F case_id=$case_id -F sample_id=$sample_id -F stdout=true -F include_details=y -F high_conf_only=$high_conf_only_str $url";
  print "Running sample $sample_id\n";
  print "cmd: $cmd\n";
  if ($first) {
    system("$cmd > $out_file");
    $first = 0;
  } else {
    system("$cmd  | grep -v '^Sample ID' | grep . >> $out_file");
  }
}
$sth_samples->finish;
$dbh->disconnect();

#/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_pub/app/storage/ProcessedResults/processed_DATA$ for fn in Sonde*;do /mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_pub/app/scripts/backend/deleteCase.pl -p $fn -c 20171011 -r;done
#system("$script_dir/refreshViews.pl -p");
