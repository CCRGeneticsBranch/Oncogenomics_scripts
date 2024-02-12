#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
require(dirname(abs_path($0))."/lib/Onco.pm");

#to find out which project has survival data, use the following SQL:
#select distinct s.project_id,s.name from patient_details p,project_samples s where p.patient_id=s.patient_id and s.exp_type='RNAseq' and class in ('overall_survival','event_free_survival','first_event','survival_status') and attr_value is not null order by project_id
my $project_id;
my $out_dir;
my $matrix_file;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -p  <integer> project id
 
  
__EOUSAGE__
my $r_path = getConfig("R_PATH");
$ENV{'PATH'}=$r_path.$ENV{'PATH'};#Ubuntu16
$ENV{'R_LIBS'}=getConfig("R_LIBS");#Ubuntu16

GetOptions (
  'p=i' => \$project_id,
);

my $script_dir = abs_path(dirname(__FILE__));

if (!$project_id) {
	die "Project ID is missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

my $survival_dir = "$script_dir/../../storage/project_data/$project_id/survival";
system("mkdir -p $survival_dir");
my $overall_survival_prefix = "$survival_dir/overall";
my $event_free_survival_prefix = "$survival_dir/event_free";
my @diags = &saveSurvivalFile($project_id, $overall_survival_prefix, $event_free_survival_prefix);
$dbh->disconnect();

my $expression_file = "$script_dir/../../storage/project_data/$project_id/expression.tpm.tsv";
if ( -s $expression_file) {
	foreach my $diagnosis(@diags) {
		print("calculating $diagnosis pvalues for overall survival\n");
		system("Rscript $script_dir/preprocessProjectExpressionSurvival.R $overall_survival_prefix.$diagnosis.tsv $expression_file $survival_dir/overall_pvalues.$diagnosis.tsv");
		print("calculating $diagnosis pvalues for event free survival\n");
		system("Rscript $script_dir/preprocessProjectExpressionSurvival.R $event_free_survival_prefix.$diagnosis.tsv $expression_file $survival_dir/event_free_pvalues.$diagnosis.tsv");
	}
}

sub saveSurvivalFile {
	my ($project_id, $overall_survival_prefix, $event_free_survival_prefix) = @_;
	my $sql_samples = "select distinct p.patient_id,s.sample_id,s.diagnosis,class,attr_value from patient_details p,project_samples s where p.patient_id=s.patient_id and s.exp_type='RNAseq' and class in ('overall_survival','event_free_survival','first_event','survival_status') and attr_value is not null and s.project_id=$project_id";
	my $sth_samples = $dbh->prepare($sql_samples);
	$sth_samples->execute();
	my %survival_data = ();
	while (my ($patient_id,$sample_id,$diagnosis,$attr_name,$attr_value) = $sth_samples->fetchrow_array) {
		$survival_data{$diagnosis}{$patient_id}{$sample_id}{$attr_name} = $attr_value;
	}
	$sth_samples->finish();
	#open(OVERALL_SURVIVAL, ">$overall_survival_prefix.any.tsv");
	#open(EVENT_FREE_SURVIVAL, ">$event_free_survival_prefix.any.tsv");
	#print "overall survival: $$overall_survival_prefix.any.tsv\nevent free survival:$$event_free_survival_prefix.any.tsv\n";

	my @diags = ();
	foreach my $diagnosis (keys %survival_data) {
		open(OVERALL_DIAG_SURVIVAL, ">$overall_survival_prefix.$diagnosis.tsv");
		open(EVENT_FREE_DIAG_SURVIVAL, ">$event_free_survival_prefix.$diagnosis.tsv");
		print OVERALL_DIAG_SURVIVAL join("\t", ("SampleID","Patient ID","Time","Status"))."\n";
	  print EVENT_FREE_DIAG_SURVIVAL join("\t", ("SampleID","Patient ID","Time","Status"))."\n";
		push @diags, $diagnosis;
		foreach my $patient_id (keys %{$survival_data{$diagnosis}}) {
			foreach my $sample_id (keys %{$survival_data{$diagnosis}{$patient_id}}) {
				if (exists $survival_data{$diagnosis}{$patient_id}{$sample_id}{"event_free_survival"}) {
					my $time = $survival_data{$diagnosis}{$patient_id}{$sample_id}{"event_free_survival"};
					if ($time =~ /^-?\d+\.?\d*$/) {
						if ($time > 0) {
							my $status = $survival_data{$diagnosis}{$patient_id}{$sample_id}{"first_event"};
							if ($status ne "0") {
								$status = "1";
							}
							#print EVENT_FREE_SURVIVAL join("\t", ($sample_id, $patient_id, $time, $status))."\n";
							print EVENT_FREE_DIAG_SURVIVAL join("\t", ($sample_id, $patient_id, $time, $status))."\n";
						}
					}
				}
				if (exists $survival_data{$diagnosis}{$patient_id}{$sample_id}{"overall_survival"}) {
					my $time = $survival_data{$diagnosis}{$patient_id}{$sample_id}{"overall_survival"};
					if ($time =~ /^-?\d+\.?\d*$/) {
						if ($time > 0) {
							my $status = $survival_data{$diagnosis}{$patient_id}{$sample_id}{"survival_status"};					
							#print OVERALL_SURVIVAL join("\t", ($sample_id, $patient_id, $time, $status))."\n";
							print OVERALL_DIAG_SURVIVAL join("\t", ($sample_id, $patient_id, $time, $status))."\n";
						}
					}
				}
			}
		}
		close(EVENT_FREE_DIAG_SURVIVAL);
		close(OVERALL_DIAG_SURVIVAL);
	}
	#close(OVERALL_SURVIVAL);
	#close(EVENT_FREE_SURVIVAL);
	return @diags;
}	
