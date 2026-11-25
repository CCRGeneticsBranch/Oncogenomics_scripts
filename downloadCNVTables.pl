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
my $type = "sequenza";

my $url = getConfig("URL")."/downloadCNV";
my $token = getConfig("TOKEN");
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project ID  
  -o  <string>  Output dir (default: $out_dir)
  -t  <string>  Type (default: $type)

Example:
  ./downloadCNVTables.pl -p 22114 
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,  
  'o=s' => \$out_dir,
  't=s' => \$type
);

if (!$project_id) {
    die "Please input project_id\n$usage";
}

if (!$type) {
    die "Please input type\n$usage";
}

if (!$out_dir) {
    die "Please input out_dir\n$usage";
}


my $dbh = getDBI();

my $cnv_table = "var_cnv_segment";
if ($type eq "cnvkit") {
  $cnv_table = "var_cnvkit_segment";
}
my $cnt_sql = "select count(*) as cnt from $cnv_table c, project_samples p where c.sample_id=p.sample_id and project_id=$project_id";
my $sth_cnv_cnt = $dbh->prepare($cnt_sql);
$sth_cnv_cnt->execute();
if (my ($cnt) = $sth_cnv_cnt->fetchrow_array) {
  if ($cnt == 0) {
    print("No data in $type!\n");
    $sth_cnv_cnt->finish;
    $dbh->disconnect();
    exit(1);
  }
}
$sth_cnv_cnt->finish;

my $sql = "select distinct c.patient_id, c.case_id, c.sample_id from $cnv_table c, project_samples p where c.sample_id=p.sample_id and project_id=$project_id";
#print "$sql\n";
print "downloading CNV data for project $project_id\n";
my $sth_cnv = $dbh->prepare($sql);
$sth_cnv->execute();

system("mkdir -p $out_dir/$project_id/cnv");
my $summary_file = "$out_dir/$project_id/cnv/$project_id.$type.summary.tsv";
open(my $summary_fh, '>', $summary_file)
  or die "Cannot write $summary_file: $!";
print $summary_fh join("\t",
  "Patient ID", "Case ID", "Sample ID",
  "Non-diploid Length", "Total Length", "Ratio",
  "A", "C", "GI", "Total segments"
), "\n";
close($summary_fh);

while (my ($patient_id, $case_id, $sample_id) = $sth_cnv->fetchrow_array) {
  my $out_file_tmp = "$out_dir/$project_id/cnv/$patient_id-$case_id-$sample_id.$type.tmp";
  my $out_file = "$out_dir/$project_id/cnv/$patient_id-$case_id-$sample_id.$type.txt";

  system(
    'curl', '--fail', '--silent', '--show-error',
    '--user-agent', 'Clinomics-CNV-download/1.0',
    '--output', $out_file_tmp,
    "$url/$token/$patient_id/$case_id/$sample_id/$type"
  ) == 0 or die "CNV download failed for $patient_id/$case_id/$sample_id\n";

  if ($type eq "sequenza") {
    open(my $input_fh, '<', $out_file_tmp)
      or die "Cannot read $out_file_tmp: $!";

    <$input_fh>; # Skip the downloaded header.
    my $summary_line = <$input_fh>;
    defined($summary_line)
      or die "Missing CNV summary for $patient_id/$case_id/$sample_id\n";
    $summary_line =~ s/\r?\n$//;

    open(my $append_fh, '>>', $summary_file)
      or die "Cannot append to $summary_file: $!";
    print $append_fh "$patient_id\t$case_id\t$sample_id\t$summary_line\n";
    close($append_fh);

    open(my $output_fh, '>', $out_file)
      or die "Cannot write $out_file: $!";
    while (my $line = <$input_fh>) {
      print $output_fh $line;
    }
    close($output_fh);
    close($input_fh);
  } else {
    require File::Copy;
    File::Copy::copy($out_file_tmp, $out_file)
      or die "Cannot copy $out_file_tmp to $out_file: $!";
  }

  unlink($out_file_tmp)
    or warn "Cannot remove $out_file_tmp: $!";
}
$sth_cnv->finish;

# get CNV summary from table first
$sql = "select distinct c.* from var_cnv_summary c, project_samples p where c.sample_id=p.sample_id and project_id=$project_id";
my $sth_cnv_summary = $dbh->prepare($sql);
$sth_cnv_summary->execute();

my %cnv_summary = ();
while (my @row = $sth_cnv_summary->fetchrow_array) {
  $cnv_summary{"$row[0]\t$row[1]\t$row[2]"} = join("\t", @row);
}
$sth_cnv_summary->finish;
my $sth_insert_cnv_summary = $dbh->prepare("insert into var_cnv_summary values(?,?,?,?,?,?,?,?,?,?)");
open(SUMMARY_FILE, "$summary_file") or die "cannot open file $summary_file";
<SUMMARY_FILE>;
while (<SUMMARY_FILE>) {
  chomp;
  my @fields = split(/\t/);
  my $key = "$fields[0]\t$fields[1]\t$fields[2]";
  if ($#fields == 10) {
    splice @fields, 3, 1;
  }
  if ($fields[8] eq "NA") {
    $fields[8] = "0";
  }
  if ($fields[9] eq "NA") {
    $fields[9] = "0";
  }
  if (!exists($cnv_summary{$key})) {
    $sth_insert_cnv_summary->execute(@fields);
  }
}


$dbh->disconnect();
my $out_zip = "$out_dir/$project_id/cnv/$project_id.$type.zip";
if ( -e $out_zip ) {
  system("rm $out_zip");
}
system("zip -j $out_zip $out_dir/$project_id/cnv/*.$type.txt");
system("rm $out_dir/$project_id/cnv/*.$type.txt");
