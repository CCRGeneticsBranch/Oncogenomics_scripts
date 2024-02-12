#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';
use Time::Piece;
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = abs_path(dirname(__FILE__));
my $avia_path = abs_path($script_dir."/../../../site_data/avia/hg19");
my $table_name="hg19_annot_oc";
my $failed_file="$avia_path/failed.all.tsv";
my $out_file;

my $usage = <<__EOUSAGE__;

#./export_new_variants.pl -o ../../../site_data/avia/hg19/new_variants.tsv

Usage:

$0 [options]

Options:

  -t            Table name (default: $table_name)
  -f            Unmapped list (default: $failed_file)
  -o            Output file
  
__EOUSAGE__



GetOptions (
	't=s' => \$table_name,
  'f=s' => \$failed_file,
  'o=s' => \$out_file
);

if (!$out_file) {
    die "Please specifiy options!\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();
my $host = getDBHost();

my %failed_vars = ();
open(FAILED_FILE, "$failed_file") or die "Cannot open file $failed_file";
while(<FAILED_FILE>) {
  chomp;
  my @fields = split(/\t/);
  next if ($#fields < 1);
  $failed_vars{$fields[0].":".$fields[1]} = "";
}

print_log("Exporting to $out_file on $host ($sid)");
my $sql = "select distinct chromosome,start_pos,end_pos,ref,alt from var_samples v where not exists(select * from $table_name a where v.chromosome=a.chr and v.start_pos=a.query_start and v.end_pos=a.query_end and v.ref=a.allele1 and v.alt=a.allele2) order by chromosome,start_pos,end_pos";
my $sth_novel = $dbh->prepare($sql);
$sth_novel->execute();
open(OUT_FILE, ">$out_file") or die "Cannot open file $out_file";
while (my @row = $sth_novel->fetchrow_array) {
  my $key = $row[0].":".$row[1];
  if (!exists $failed_vars{$key}) {
	 print OUT_FILE join("\t",@row)."\n";
  } else {
    print "$key in unmapped table\n";
  }

}
close(OUT_FILE);
system("chmod 775 $out_file");
$dbh->disconnect();
print_log("Done");