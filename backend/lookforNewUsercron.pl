#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use File::Basename;
use MIME::Lite; 

my $refresh_all = 0;
my $do_cnv = 0;
my $do_prj_summary = 0;
my $do_avia = 0;
my $do_cohort = 0;

my $usage = <<__EOUSAGE__;

Usage:

$0   
__EOUSAGE__
  # -a            Refresh all
  # -c            Refresh CNV views
  # -p            Refresh Project views
  # -v            Refresh AVIA views
  # -h            Refresh Cohort views


GetOptions (
  # 'a' => \$refresh_all,
  # 'c' => \$do_cnv,
  # 'p' => \$do_prj_summary,
  # 'v' => \$do_avia,
  # 'h' => \$do_cohort
);


my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd,$port) = split(/\t/, $db_config[0]);
my $dbh = DBI->connect( "dbi:Oracle:host=$host;sid=$sid;port=$port", $username, $passwd, {
    AutoCommit => 1,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);
my $get_user_id=$dbh->prepare("select email,TO_CHAR( activated_at, 'FMMonth DD, YYYY' ) activated ,TO_CHAR( last_login, 'FMMonth DD, YYYY' ) last_login from  users where activated_at >= sysdate -7 and id not in (select user_id from user_projects)");
$get_user_id->execute();
my ($email,$activated_at,$last_login);
$get_user_id->bind_columns(\$email,\$activated_at,\$last_login);
my $found=0;
my $content= "The following users do not have any projects associated with them in the Clinomics Genomics Portal:\n<table><tr><th>User</th><th>Last login</th><th>Activated at</th></tr>";
while($get_user_id->fetch()){
	$found++;
	$content.= "<tr><td>$email</td><td>$last_login</td><td>$activated_at</td></tr>";
}
$content.= "</table><br />Please contact users or add them to a project.  If there is no email address (just user), this is most likely a reviewer.  ";
if ($found>0){
	# print "$content";
	sendEmail($content,"OncoPub");
}else{
	print "There were no new users without projects for the Portal. Cron ran at " .`date`;
}

sub sendEmail {
	my ($content, $database_name,$recipient) = @_;
	my $subject   = "Clinomics Genomics Portal User Update";
	my $sender    = 'oncogenomics@mail.nih.gov';
	if (!$recipient || $recipient==''){
		$recipient = 'vuonghm@mail.nih.gov,hsien-chao.chou@nih.gov';#,khanjav@mail.nih.gov,weij@mail.nih.gov';
	}
	my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $recipient,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $content,
	);

	$mime->send();
}

#$dbh->do("BEGIN Dbms_Mview.Refresh('VAR_PATIENT_ANNOTATION','C');END;");
# $dbh->disconnect();
# print "done updating on $host ($sid)\n";
