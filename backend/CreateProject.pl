#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use LWP::Simple;
use Scalar::Util qw(looks_like_number);
use Try::Tiny;
use MIME::Lite; 
use File::Temp qw/ tempfile tempdir /;
use POSIX;
use Cwd 'abs_path';

local $SIG{__WARN__} = sub {
  my $message = shift;
  if ($message =~ /uninitialized/) {
    die "Warning:$message";
  }
};

my $dir;
my $target_patient;
my $target_case;
my $patient_data ="";
my $project_name ="";
my $project_description="";
my $email="";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:
  -p  <string>  path to project data (Sample ID and Patient ID)
  -n  <string>  Project name
  -d  <string>  Project description
  -e  <string>  User email
  -v  <string>  version
  
__EOUSAGE__



GetOptions (

  'n=s' => \$project_name,
  'p=s' => \$patient_data,
  'd=s' => \$project_description,
  'e=s' => \$email,
  'v=s' => \$version,

);
my $script_dir = abs_path(dirname(__FILE__));
my $app_path = $script_dir."/../../..";
my $storage_path = $script_dir."/../../storage/ProcessedResults/";

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);
my $sql="";
my $get_project_id=$dbh->prepare("select id from projects where name=?");  
my $insert_project_patients = $dbh->prepare("insert into project_patients (project_id,patient_id,case_name) VALUES (?,?,?)");
my $get_case_name=$dbh->prepare("select distinct case_name from processed_sample_cases where patient_id=? and sample_id=?");

$sql="insert into projects (name,ispublic,description,user_id,created_at,updated_at,isstudy,status,version) VALUES ('$project_name','0','$project_description',1602,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,'1','0','$version')";
$dbh->do($sql);   
$dbh->commit();

$get_project_id->execute($project_name);
  my @row = $get_project_id->fetchrow_array;
  my $project_id=$row[0];
my $no_cases='';
open(my $fh, '<', $patient_data) or die "Could not open file '$patient_data' $!";

while (my $row = <$fh>) {
  chomp $row;
  my @col=split("\t",$row);
  my $patient_id=$col[0];
  my $sample_id=$col[1];
  
  $get_case_name->execute($patient_id,$sample_id);
  #print $row."\n";
  try{
      my @case_name_row = $get_case_name->fetchrow_array;
      print $row."\t".$case_name_row[0]."\n";
      $sql ="insert into project_patients (project_id,patient_id,case_name) VALUES ('$project_id','$patient_id','$case_name_row[0]')";
      print $sql."\n";
      $dbh->do($sql);   
    $dbh->commit();
  }
  catch{
    print $no_cases=$no_cases.$sample_id."\n";
  }
}
open(my $fh_no, '>', $app_path."/storage/logs/CreateProjectLogs.txt") or die "Could not open file '$patient_data' $!";
print "NO CASES\n$no_cases";
print $fh_no "project id: ".$project_id."\n";
print $fh_no "project name ".$project_name."\n";
print $fh_no "file path: ".$patient_data."\n";
print $fh_no $no_cases."\n\n\n";

print $project_name."\n";
print "$project_description\n";
print $project_id."\n";
my $path=$script_dir."/preprocessProjectMaster.pl\n";
print $path;
system("qsub -k oe -v path=".$path.",project_id=".$project_id.",email=".$email." ".$app_path."/../scripts/backend/submit_NewProject.pbs");


#system("qsub -k oe -v project_id=".$project_id.",email=".$email.",output= ".$app_path."/storage/project_data"." ".$app_path."/scripts/preprocessProjectMaster.pbs");
print "END\n";
#$dbh->do("BEGIN Dbms_Mview.Refresh('project_samples','C');END;");
#$dbh->do("BEGIN Dbms_Mview.Refresh('project_sample_summary','C');END;");
