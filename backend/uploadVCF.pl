#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use File::Basename;
use DBD::Oracle qw(:ora_types);
use Getopt::Long qw(GetOptions);
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $input_file;
my $user_id;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -i  <string>  VCF file
  -u  <int>     User ID
  
__EOUSAGE__



GetOptions (
  'u=i' => \$user_id,
  'i=s' => \$input_file
);

if (!$input_file || !$user_id) {
    die "Some parameters are missing\n$usage";
}
my $file_name = basename($input_file);
my $script_dir = abs_path(dirname(__FILE__));
my $app_path = $script_dir."/../..";

my @lines = readpipe("$script_dir/vcf2txt.pl $input_file $app_path/bin/ANNOVAR/2016-02-01");
my $dbh = getDBI();
print("Inserting ...");
$dbh->do("delete var_upload where file_name='$file_name' and user_id=$user_id");
$dbh->do("delete var_upload_details where patient_id='$file_name'");
my $sql = "insert into var_upload_details values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
$dbh->do("insert into var_upload values('$file_name',CURRENT_TIMESTAMP ,$user_id)");
my $sth = $dbh->prepare($sql);
foreach my $line(@lines) {
	chomp $line;
	my @fields = split(/\t/, $line);
	next if ($fields[0] eq "Chr");
	my $vaf = $fields[12]/$fields[10];
	$sth->execute($fields[0], $fields[1], $fields[2], $fields[3], $fields[4],$file_name,$file_name,$file_name,$file_name,"VCF4",$fields[5],0,"variants","tumor","Exome","self",$fields[12],$fields[10],0,0,0,0,$vaf,$vaf,0);
}
$dbh->commit();
$dbh->disconnect();
print(" done\n");

