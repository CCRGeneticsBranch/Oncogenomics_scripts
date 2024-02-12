#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
use MIME::Lite;
require(dirname(abs_path($0))."/lib/Onco.pm");

my $project_id;
my $email = "";
my $url = getConfig("url");
my $project_name = "";
my $include_pub=0;
my $download_var=0;
my $download_vcf=0;
my $download_cnv=0;
my $download_mixcr=0;
my $process_gt=0;
my $no_exp=0;

$ENV{'PATH'}=getConfig("R_PATH").$ENV{'PATH'};#Ubuntu16
$ENV{'R_LIBS'}=getConfig("R_LIBS");#Ubuntu16

my $script_dir = abs_path(dirname(__FILE__));
my $app_path = abs_path($script_dir."/../..");
my $out_dir = "$app_path/storage/project_data";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

options:

  -p  <string> Project id or 'all' for all projects or update list file
  -o  <string> Output directory (default: $out_dir)
  -e  <string> Notification email
  -u  <string> OncogenomicsDB URL  
  -i           Include public projects
  -n           Dot not process expression data
  -v           Download variants
  -c           Download CNVs
  -f           Download VCFs
  -m           Download Mixcr
  -g           Process genotyping
  
__EOUSAGE__



GetOptions (
  'p=s' => \$project_id,
  'o=s' => \$out_dir,
  'e=s' => \$email,
  'u=s' => \$url,
  'i'   => \$include_pub,
  'n'   => \$no_exp,
  'v'   => \$download_var,
  'f'   => \$download_vcf,
  'c'   => \$download_cnv,
  'm'   => \$download_mixcr,
  'g'   => \$process_gt
);

if (!$project_id) {
    die "Project id is missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

my %projects = ();
if ($project_id eq "all") {
	my $sql = "select id, name, ispublic from projects";
	my $sth = $dbh->prepare($sql);
	$sth->execute();
	while (my ($id, $name, $ispublic) = $sth->fetchrow_array) {
		if ($ispublic eq "0" || $include_pub) {
			$projects{$id} = $name;
		}
	}
	$sth->finish();
} elsif ($project_id =~ /^\d+$/) {
	my $sql = "select id, name from projects where id = $project_id";
	my $sth = $dbh->prepare($sql);
	$sth->execute();
	if (my ($id, $name) = $sth->fetchrow_array) {
		$projects{$id} = $name;
	} else {
		$sth->finish();
		$dbh->disconnect();
		die("Project $project_id cannot be found!\n");
	}
} else {
	open(FILE, "$project_id") or die "Cannot open file $project_id";
	while(<FILE>) {
		chomp;
		my ($patient_id, $case_id) = $_ =~ /(.*)\/(.*)\/.*/;
		print("$patient_id, $case_id\n");
		#my $sth = $dbh->prepare("select distinct project_id, name from project_cases c, projects p where c.project_id=p.id and patient_id='$patient_id' and case_id='$case_id'");
		my $sth = $dbh->prepare("select distinct project_id,name from project_sample_mapping m, sample_case_mapping s,projects p where m.sample_id=s.sample_id and m.project_id=p.id and s.patient_id='$patient_id' and s.case_name='$case_id'");
		$sth->execute();
		while (my ($pid, $name) = $sth->fetchrow_array) {
			$projects{$pid} = $name;
		}
	}	
}

$dbh->do("alter index PROJECT_VALUES_PK INVISIBLE");
my $all_start = time;
foreach my $pid (keys %projects) {
	print "Clean up old data...$sid";
	my $start = time;
	if (! $no_exp) {
		$dbh->do("delete from PROJECT_VALUES where project_id=$pid");	
		$dbh->do("update PROJECTS set status=0 where id=$pid");	
		$dbh->commit();
	}
	my $duration = time - $start;
	print "time: $duration s\n";

	$start = time;
	my @types = ('ensembl');
	my @levels = ('gene');
	my @thrs = ();
	foreach my $type (@types) {
		foreach my $level (@levels) {
			#my $thr = threads->create(\&process, $pid, $type, $level);
			if (! $no_exp) {
				process($pid, $type, $level);
			}
			#push(@thrs, $thr);
		}
	}

	#foreach my $thr(@thrs) {
	#	$thr->join();
	#}

	$duration = time - $start;
	#make variants and VCF zip files
	if ($download_var) {
		system("$script_dir/downloadVarAnnotation.pl -p $pid");		
	}
	if ($download_vcf) {
		system("$script_dir/backend/downloadProjectVCFs.pl -p $pid");
	}
	if ($download_cnv) {
		system("$script_dir/downloadCNVTables.pl -p $pid");
		system("$script_dir/generateCNVMatrix.pl -p $pid");
		system("$script_dir/generateCNVMatrix.pl -p $pid -t cnvkit");
	}
	if ($download_mixcr) {
		system("$script_dir/downloadMixcer.pl -p $pid");
	}
	if ($process_gt) {
		system("$script_dir/backend/scoreProjectGenotypes.pl -p $pid");
	}
	system("chmod -R g+w $out_dir/$pid");
	print "Total time for project $pid: $duration s\n";
}
$dbh->do("alter index PROJECT_VALUES_PK VISIBLE");
$dbh->do("alter index PROJECT_STAT_PK VISIBLE");

$dbh->disconnect();
my $total_duration = time - $all_start;
print "total time: $total_duration s\n";
my $size = keys %projects;
if ($project_id ne "all" && $email ne "" && $size > 0) {
	sendEmail($email, $url, \%projects);
}

sub process {
	my ($pid, $type, $level) = @_;
	my $out_dir = &formatDir($out_dir)."$pid";
	system("mkdir -p $out_dir");
	my $cmd = "$script_dir/preprocessProject.pl -p $pid -o $out_dir -t $type -l $level";
	print "$cmd\n";
	eval{
		system($cmd);	
	};
	if ($? || $@){
		print "on $pid ($sid) could not run $cmd\nOutput directory set to $out_dir\n";
	}
}

sub sendEmail {
	my ($email, $url, $projects_ref) = @_;
	my $subject   = "OncogenomicsDB project status";
	my $sender    = 'oncogenomics@mail.nih.gov';
	my $recipient = $email;
	my %projects = %{$projects_ref};
	my $content = "<H4> The following project level data have been processed</H4><table border=1 cellspacing=2><th>Project ID</th><th>Name</th>";
	foreach my $pid (keys %projects) {
		my $name = $projects{$pid};
		$content = $content."<tr><td>$pid</td><td><a href=$url/viewProjectDetails/$pid>$name</a></td>";
	}
	$content = $content."</table><br>Oncogenomics Team.";
	my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $recipient,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $content,
	);

	$mime->send();
}
