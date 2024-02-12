#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);

my $processed_data_dir = abs_path($script_dir."/../../../storage/ProcessedResults");
my $project_id;
my $remove_folder = 0;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Project ID
  -r            Remove project folder
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  'r' => \$remove_folder  
);

if (!$project_id) {
    die "Please input project_id\n$usage";
}

my $dbh = getDBI();

$dbh->do("delete projects where id=$project_id");
$dbh->do("delete project_patients where project_id='$project_id'");
$dbh->do("delete project_values where project_id='$project_id'");
$dbh->do("delete project_stat where project_id='$project_id'");
$dbh->do("delete project_samples where project_id='$project_id'");

if ($remove_folder) {
  system("rm -rf $processed_data_dir$project_id");
}

$dbh->commit();
$dbh->disconnect();
