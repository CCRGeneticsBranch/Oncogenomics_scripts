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
my $type="overall";
my $run_perm="Y";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -p  <integer> project id
  -t  <string> overall or event_free (default: $type)
  -r  <string> run permutation test (Y/N, default: $run_perm)
 
  
__EOUSAGE__
my $r_path = getConfig("R_PATH");
$ENV{'PATH'}=$r_path.$ENV{'PATH'};#Ubuntu16
$ENV{'R_LIBS'}=getConfig("R_LIBS");#Ubuntu16

GetOptions (
  'p=i' => \$project_id,
  't=s' => \$type,
  'r=s' => \$run_perm
);

my $script_dir = abs_path(dirname(__FILE__));

if (!$project_id) {
	die "Project ID is missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

my $survival_dir = "$script_dir/../../storage/project_data/$project_id/survival";
system("mkdir -p $survival_dir");

my @diags = &saveSurvivalFile($project_id, $type);
$dbh->disconnect();

my $expression_file = "$script_dir/../../storage/project_data/$project_id/expression.tpm.tsv";
if ( -s $expression_file) {
	foreach my $diagnosis(@diags) {
		print("calculating $diagnosis pvalues for $type survival\n");
		system("Rscript $script_dir/preprocessProjectExpressionSurvivalKMCut.R $survival_dir/$type.$diagnosis.tsv $expression_file ${diagnosis}.$type $run_perm");
	}
}

sub saveSurvivalFile {
	my ($project_id, $type) = @_;
	my $survival_prefix = "$survival_dir/$type";
	my $status_name = ($type eq "overall")? 'survival_status' : 'first_event';
	my $sql_samples = "select distinct p.patient_id,s.sample_id,s.diagnosis,class,attr_value from patient_details p,project_samples s where p.patient_id=s.patient_id and s.exp_type='RNAseq' and class in ('${type}_survival','$status_name') and attr_value is not null and s.project_id=$project_id";
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
		open(DIAG_SURVIVAL, ">$survival_prefix.$diagnosis.tsv");
		print DIAG_SURVIVAL join("\t", ("sample_id","patient_id","stime","scens"))."\n";
	  push @diags, $diagnosis;
		foreach my $patient_id (keys %{$survival_data{$diagnosis}}) {
			foreach my $sample_id (keys %{$survival_data{$diagnosis}{$patient_id}}) {
				if (exists $survival_data{$diagnosis}{$patient_id}{$sample_id}{"${type}_survival"}) {
					my $time = $survival_data{$diagnosis}{$patient_id}{$sample_id}{"${type}_survival"};
					if ($time =~ /^-?\d+\.?\d*$/) {
						if ($time > 0) {
							my $status = $survival_data{$diagnosis}{$patient_id}{$sample_id}{$status_name};
							if ($status ne "0") {
								$status = "1";
							}
							#print EVENT_FREE_SURVIVAL join("\t", ($sample_id, $patient_id, $time, $status))."\n";
							print DIAG_SURVIVAL join("\t", ($sample_id, $patient_id, $time, $status))."\n";
						}
					}
				}
			}
		}
		close(DIAG_SURVIVAL);
	}
	return @diags;
}	
