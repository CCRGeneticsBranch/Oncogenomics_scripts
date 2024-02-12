#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
use Data::Dumper;
use MIME::Lite;
require(dirname(abs_path($0))."/lib/Onco.pm");

my $project_id;
my $email = "";
my $url = getConfig("url");
my $project_name = "";
my $include_pub=0;

my $script_dir = abs_path(dirname(__FILE__));
my $app_path = abs_path($script_dir."/../..");
my $out_dir = "$app_path/storage/project_data";
my $hc=0;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

options:

  -p  <string> Project id or 'all' for all projects
  -o  <string> Output directory (default: $out_dir)
  -e  <string> Notification email
  -u  <string> OncogenomicsDB URL  
  -h           High confident only
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  'o=s' => \$out_dir,
  'e=s' => \$email,
  'u=s' => \$url,
  'h' => \$hc  
);
my $start = time;
if (!$project_id) {
    die "Project id is missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

my $pid_clause = "";
if ($project_id ne "all") {
	$pid_clause = " and project_id = $project_id";
}
my $sql = "select distinct project_id,p2.patient_id,p2.case_id,p2.type from project_cases p1, var_cases p2 where p1.patient_id=p2.patient_id and p1.case_id=p2.case_id and p2.type<>'hotspot' and p2.type <> 'fusion' and p2.case_id is not null $pid_clause";
print "$sql\n";
my $sth = $dbh->prepare($sql);
$sth->execute();
my %data = ();
while (my @row = $sth->fetchrow_array) {
	if (!$data{$row[0]}) {
		$data{$row[0]} = [];
	}
	push @{$data{$row[0]}}, \@row;
}
$sth->finish();
my $high_conf = ($hc)? "true" : "false";
foreach my $pid (keys %data) {	
	my $var_dir = "$out_dir/$pid/variants";
	system("mkdir -p $var_dir");
	my @rows = @{$data{$pid}};
	my %types = ();
	for my $r(@rows) {
		my @row = @{$r};
		print join("\t", @row)."\n";
		my $cmd = "curl -F project_id=$row[0] -F type=$row[3] -F annotation=avia -F patient_id=$row[1] -F case_id=$row[2] -F stdout=true -F include_details=true -F high_conf_only=$high_conf $url/downloadVariants > $var_dir/$row[1].$row[2].$row[3].tsv";
		$types{$row[3]} = '';
		system($cmd);
	}
	system("rm $var_dir/*.zip");	
	foreach my $type (keys %types) {
		system("rm $var_dir/$pid.$type.txt");
		system("cat $var_dir/*.$type.tsv > $var_dir/$pid.$type.txt.tmp");
		system("head -1 $var_dir/$pid.$type.txt.tmp > $var_dir/$pid.$type.txt");
		system("grep -v '^Sample ID' $var_dir/$pid.$type.txt.tmp >> $var_dir/$pid.$type.txt");
		system("zip -j $var_dir/$pid.$type.zip $var_dir/*.$type.tsv");
		system("zip -j $var_dir/$pid.$type.merged.zip $var_dir/$pid.$type.txt");
	}
	#print("$cmd\n");
	#system($cmd);
	
}

$dbh->disconnect();
my $total_duration = time - $start;
print "total time: $total_duration s\n";
if ($project_id ne "all" && $email ne "") {
	sendEmail($email, $url, $project_id, $project_name);
}

sub sendEmail {
	my ($email, $url, $project_id, $project_name) = @_;
	my $subject   = "OncogenomicsDB project status";
	my $sender    = 'oncogenomics@mail.nih.gov';
	my $recipient = $email;
	my $content = "<H4>Project <a href=$url/viewProjectDetails/$project_id>$project_name</a> is ready!</H4>";
	my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $recipient,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $content,
	);

	$mime->send();
}
