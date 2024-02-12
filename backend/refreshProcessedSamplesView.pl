#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;

my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 1,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);

$dbh->do("BEGIN Dbms_Mview.Refresh('processed_sample_cases','C');END;");
#$dbh->do("BEGIN Dbms_Mview.Refresh('VAR_PATIENT_ANNOTATION','C');END;");
$dbh->do("truncate table cache");
$dbh->disconnect();
