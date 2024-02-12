#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);

my $host;
my $sid;
my $username;
my $passwd;
my $input_file;
my $table_name;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -h  <string>  DB Host
  -s  <string>  Instance ID
  -u  <string>  User name
  -p  <string>  Password
  -i  <string>  Input text file
  -t  <string>  Table name
  
__EOUSAGE__



GetOptions (
  'h=s' => \$host,
  's=s' => \$sid,
  'u=s' => \$username,
  'p=s' => \$passwd,
  't=s' => \$table_name,
  'i=s' => \$input_file
);

if (!$input_file || !$table_name || !$host || !$sid || !$username || !$passwd) {
    die "Some parameters are missing\n$usage";
}

my $dbh = DBI->connect( "dbi:Oracle:host=$host;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,
}) || die( $DBI::errstr . "\n" );

$dbh->do("delete from $table_name");
open(IN_FILE, "$input_file") or die "Cannot open file $input_file";

my $line = <IN_FILE>;
$line =~ s/\r\n$//g;
chomp $line;
my @header = split(/\t/,$line);
my $num_fields = $#header;
my $sql .= "insert into $table_name values(?,?,?)";

my $sth = $dbh->prepare($sql);

while (<IN_FILE>) {  
	chomp;  
	my @fields = split(/\t/);
	next if ($#fields < $num_fields);
  my $key1 = $fields[0];
	for (my $i=1;$i<=$#fields;$i++) {
    my $key2 = $header[$i];
    my $value = $fields[$i];
    $value =~ s/\r$//g;
    if ($value ne "") {
      $sth->execute($key1, $key2, $value);
    }
	}	
}

close(IN_FILE);
$dbh->commit();
$dbh->disconnect();


