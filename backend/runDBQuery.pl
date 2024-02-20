#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $sql=$ARGV[0];

if (!$sql) {
  die "usage: runDBQuery.pl 'SQL command'"; 
}

my $dbh = getDBI();

my $sth = $dbh->prepare($sql);
$sth->execute();
while (my @row = $sth->fetchrow_array) {
  print join("\t", @row)."\n";  
}
$sth->finish();
$dbh->disconnect();
