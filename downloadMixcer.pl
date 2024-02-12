#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/lib/Onco.pm");

my $script_dir = dirname(__FILE__);
my $app_path = abs_path($script_dir."/../..");
my $out_dir = "$app_path/storage/project_data";
my $project_id;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project ID  
  -o  <string>  Output dir (default: $out_dir)

Example:
  ./downloadMixcr.pl -p 22114 
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,  
  'o=s' => \$out_dir
);

if (!$project_id) {
    die "Please input project_id\n$usage";
}

if (!$out_dir) {
    die "Please input out_dir\n$usage";
}

system("mkdir -p $out_dir/$project_id/mixcr");

my $dbh = getDBI();
$dbh->{'LongReadLen'} = 512 * 1024; 
$dbh->{'LongTruncOk'} = 1;
my $start = time;
my $summary_sql = "select p.tissue_cat as TISSUE_CATEGORY,p.tissue_type,m.* from mixcr_summary m,project_samples p where p.project_id=$project_id and p.sample_id=m.sample_id and p.exp_type='RNAseq'";
my $clones_sql = "select p.tissue_cat as TISSUE_CATEGORY,p.tissue_type,m.* from mixcr m,project_samples p where p.project_id=$project_id and p.sample_id=m.sample_id and p.exp_type='RNAseq'";
my $sth_summary = $dbh->prepare($summary_sql);
my $sth_clones = $dbh->prepare($clones_sql);
$sth_summary->execute();
my $bcr_file = "$out_dir/$project_id/mixcr/Mixcr_BCR_clones_$project_id.txt";
my $tcr_file = "$out_dir/$project_id/mixcr/Mixcr_TCR_clones_$project_id.txt";
my $bcr_summary_file = "$out_dir/$project_id/mixcr/Mixcr_BCR_summary_$project_id.txt";
my $tcr_summary_file = "$out_dir/$project_id/mixcr/Mixcr_TCR_summary_$project_id.txt";
my $summary_header = "TISSUE_CATEGORY\tTISSUE_TYPE\tPATIENT_ID\tCASE_ID\tSAMPLE_ID\tEXP_TYPE\tCHAIN\tMETADATA_BLANK\tCOUNT\tDIVERSITY\tMEAN_FREQUENCY\tGEOMEAN_FREQUENCY\tNC_DIVERSITY\tNC_FREQUENCY\tMEAN_CDR3NT_LENGTH\tMEAN_INSERT_SIZE\tMEAN_NDN_SIZE\tCONVERGENCE";
my $clone_header = "TISSUE_CATEGORY\tTISSUE_TYPE\tPATIENT_ID\tCASE_ID\tSAMPLE_ID\tEXP_TYPE\tCHAIN\tCOUNT\tFREQ\tCDR3NT\tCDR3AA\tV\tD\tJ\tVEND\tDSTART\tDEND\tJSTART";
open(BCR_FILE, ">$bcr_file") or die "Cannot write file $bcr_file";
open(TCR_FILE, ">$tcr_file") or die "Cannot write file $tcr_file";
open(BCR_SUMMARY_FILE, ">$bcr_summary_file") or die "Cannot write file $bcr_summary_file";
open(TCR_SUMMARY_FILE, ">$tcr_summary_file") or die "Cannot write file $tcr_summary_file";
print "saving Mixcr summary for project $project_id\n";
print TCR_SUMMARY_FILE "$summary_header\n";
print BCR_SUMMARY_FILE "$summary_header\n";
while (my @fields = $sth_summary->fetchrow_array) {
  if ($fields[6] =~ /^TR/) {
    print TCR_SUMMARY_FILE join("\t", @fields)."\n";    
  } else {
    print BCR_SUMMARY_FILE join("\t", @fields)."\n";    
  }
}
$sth_summary->finish;
close(BCR_SUMMARY_FILE);
close(TCR_SUMMARY_FILE);
$sth_clones->execute();
print "saving Mixcr clones for project $project_id\n";
print TCR_FILE "$clone_header\n";
print BCR_FILE "$clone_header\n";
while (my @fields = $sth_clones->fetchrow_array) {
  if ($fields[6] =~ /^TR/) {
    print TCR_FILE join("\t", @fields)."\n";    
  } else {
    print BCR_FILE join("\t", @fields)."\n";    
  }
}
$sth_clones->finish;
close(BCR_FILE);
close(TCR_FILE);
$dbh->disconnect();
my $duration = time - $start;
print "Download time: $duration s\n";

$start = time;
my $bcr_zip = "$out_dir/$project_id/mixcr/Mixcr_BCR_clones_$project_id.zip";
if ( -e $bcr_zip ) {
  system("rm $bcr_zip");
}
system("zip -j $bcr_zip $bcr_file");

my $tcr_zip = "$out_dir/$project_id/mixcr/Mixcr_TCR_clones_$project_id.zip";
if ( -e $tcr_zip ) {
  system("rm $tcr_zip");
}
system("zip -j $tcr_zip $tcr_file");

system("rm $tcr_file $bcr_file");
$duration = time - $start;
print "Zip time: $duration s\n";