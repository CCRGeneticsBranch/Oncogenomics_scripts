#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Try::Tiny;
use MIME::Lite; 

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $sample_id="";
my $patient_id="";
my $case_id="";
my $type="";
my $status="";
my $user='';

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -i  <string>  Sample ID
  -p  <string>  Patient ID
  -c  <string>  Case ID
  -t  <string>  Type
  -r  <string>  User
  
__EOUSAGE__



GetOptions (
  'p=s' => \$patient_id,
  'c=s' => \$case_id,
  't=s' => \$type,
  'u=s' => \$status,
  'r=s' => \$user,
);

#my $content="Patient ID: ".$patient_id."\n"."CASE ID: ".$case_id."\n"."Type: ".$type."\n"."Status: ".$status."\n";

my $content='<h2>The following has been signed out:</h2>

    <table id="log" border=1 cellspacing="2" width="60%">
    	<thead><tr><th>Patient ID</th><th>Case ID</th><th>Type</th><th>Status</th><th>User</th></tr></thead>
    	<tbody><td>'.$patient_id.'</td><td>'.$case_id.'</td><td>'.$type.'</td><td>'.$status.'</td><td>'.$user.'</td></tbody>
    </table>';
    
&sendEmail($content, 'manoj.tyagi@nih.gov,weij@mail.nih.gov');
	

sub sendEmail {
	my ($content, $recipient) = @_;
	my $subject   = "OncogenomicsDB Signout Notification";
	my $sender    = 'oncogenomics@mail.nih.gov';
	#my $recipient = 'hsien-chao.chou@nih.gov, rajesh.patidar@nih.gov, manoj.tyagi@nih.gov, yujin.lee@nih.gov, wangc@mail.nih.gov';
	
	my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $recipient,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $content,
	);

	$mime->send();
}
