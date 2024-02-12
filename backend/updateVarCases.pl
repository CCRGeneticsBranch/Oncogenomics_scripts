#!/usr/bin/env perl
# Note to developers debugging this code.  This code written by either Hsien Chao or Scott Goldweber 
# This update script requires that there are at least one variant in the VAR_SAMPLES table for a particular patient.
# If it does not exist, it will keep the case_name fields ='' in the CASES and SAMPLE_CASES table
# Without the case_name information in the table, the application will not function\
# HR added code to send email so the lab can manually review 
# --HR 2019/08/15
use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $default_case_name = "20160415";
my $verbose = 0;
my $out_path = dirname(abs_path($0))."/../../../site_data/storage/logs";
$out_path = `realpath $out_path`;
chomp $out_path;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -c  <string>  Default case name (default: $default_case_name)
  -o  <string>  Output dir (default: $out_path)
  -v            Verbose output
  
__EOUSAGE__



GetOptions (
  'c=s' => \$default_case_name,
  'v' => \$verbose
);

my $script_dir = dirname(__FILE__);

my $dbh = getDBI();

my $sth_read_cases = $dbh->prepare("select patient_id, case_id, version, path from processed_cases where status <> 'not_successful'");
#my $sth_var_samples = $dbh->prepare("select distinct patient_id, case_id, sample_id from var_samples");
my $sth_var_samples = $dbh->prepare("select distinct * from (select distinct patient_id, case_id, sample_id from var_samples union select distinct patient_id, case_id, sample_id from var_qc)");
my $sth_sample_cases = $dbh->prepare("select distinct patient_id, case_name, sample_id from sample_cases where exp_type <> 'Methylseq'");
my $sth_write_cases = $dbh->prepare("update sample_case_mapping set case_id=?, match_type=? where case_name=? and patient_id=?");
my $sth_orphan_cases = $dbh->prepare("select patient_id,case_id,path from processed_cases p where not exists(select * from sample_case_mapping c where p.patient_id=c.patient_id and p.case_id=c.case_id) order by patient_id,case_id");
#my $sth_write_var_cases = $dbh->prepare("update var_type set case_name=? where case_id=? and patient_id=?");
my %processed_cases = ();
my %processed_cases_path = ();
my %processed_samples = ();
my %master_file_samples = ();
my %sample_cases = ();
my %case_samples = ();

$sth_read_cases->execute();
while (my ($patient_id, $case_id, $version, $path) = $sth_read_cases->fetchrow_array) {
	if (!$version) {
		$version = "NA";
	}
	$version =~ s/dev/\.0dev/;
	$version =~ s/21/2\.1/;
	$processed_cases{$patient_id}{$case_id} = $version;
	$processed_cases_path{$patient_id}{$case_id} = $path;
}
#processed samples
$sth_var_samples->execute();
while (my ($patient_id, $case_id, $sample_id) = $sth_var_samples->fetchrow_array) {
	$processed_samples{$patient_id}{$case_id}{$sample_id} = '';
}
$sth_var_samples->finish;

#case in master file
$sth_sample_cases->execute();
while (my ($patient_id, $case_name, $sample_id) = $sth_sample_cases->fetchrow_array) {
	push @{$master_file_samples{$patient_id}{$case_name}}, $sample_id;
}
$sth_sample_cases->finish;

#open(PERFECT_MATCH, ">$out_path/perfectly_matched_cases.txt");
#print("$out_path/perfectly_matched_cases.txt\n");
#open(PARTIAL_MATCH, ">$out_path/partial_matched_cases.txt");
#open(NOTMATCH, ">$out_path/notmatched_cases.txt");
#open(NOT_PIPELINE, ">$out_path/processed_not_pipeline_cases.txt");
#open(PARTIAL_PROCESSED, ">$out_path/partial_processed_cases.txt");
#open(NEW_PATIENT, ">$out_path/new_patient_cases.txt");

#check all patients in master file
foreach my $patient_id (sort { $master_file_samples{$b} <=> $master_file_samples{$a} } keys %master_file_samples) {
	my %case_names = %{$master_file_samples{$patient_id}};
	#check all cases in master file
	foreach my $case_name (sort { $case_names{$b} <=> $case_names{$a} } keys %case_names) {
		#if not processed at all
		if (!exists $processed_samples{$patient_id}) {
			#if TCGA or GTEX
			if (exists $processed_cases{$patient_id}{$case_name}) {
				#print NOT_PIPELINE "$patient_id\t$case_name\n";
				$sth_write_cases->execute($case_name, "not_pipeline", $case_name, $patient_id);
			} else {
				#print NEW_PATIENT "$patient_id\t$case_name\n";
				$sth_write_cases->execute("", "new_patient", $case_name, $patient_id);
			}
			last;
		} else {
			my @case_ids = sort(keys %{$processed_samples{$patient_id}});
			my @samples = @{$master_file_samples{$patient_id}{$case_name}};
			my $total_master_samples = $#samples + 1;
			my $perfect_case_id = "";
			my $perfect_version = "";
			my $partial_case_id = "";
			my $partial_processed_case_id = "";
			my $partial_processed_cnt = 0;
			#check all processed cases
			foreach my $case_id(@case_ids) {
				#check every sample in this case_name
				my $match_cnt = 0;
				foreach my $sample_id(@samples) {
					if (exists $processed_samples{$patient_id}{$case_id}{$sample_id}) {
						$match_cnt++;						
					} 
				}
				my @processed_samples = keys %{$processed_samples{$patient_id}{$case_id}};
				my $total_processed_samples = $#processed_samples + 1;
				if ($total_master_samples == $total_processed_samples && $match_cnt == $total_master_samples) {
					my $version = $processed_cases{$patient_id}{$case_id};
					if (!$version) {
						#print("$patient_id/$case_id not in processed_cases\n");
					} else {
						# if current case id is the same as case name or better version
						if ($perfect_version lt $version || $case_id eq $case_name) {
							$perfect_version = $version;
							$perfect_case_id = $case_id;
						}
					}					
				}
				if ($total_master_samples < $total_processed_samples && $match_cnt == $total_master_samples) {
					$partial_case_id = $case_id;
				}
				if ($total_master_samples > $total_processed_samples && $match_cnt == $total_processed_samples) {
					if ($match_cnt > $partial_processed_cnt) {
						$partial_processed_case_id = $case_id;
						$partial_processed_cnt = $match_cnt;
					}					
				}
			}
			# priority: perfect > partial matched > partial processed > not processed
			if ($perfect_case_id ne '' ) {
				#print PERFECT_MATCH "$patient_id\t$case_name\t$perfect_case_id\n";
				$sth_write_cases->execute($perfect_case_id, "matched", $case_name, $patient_id);
			} else {
				if ($partial_case_id ne '' ) {
					#print PARTIAL_MATCH "$patient_id\t$case_name\t$partial_case_id\n";
					my $path = $processed_cases_path{$patient_id}{$partial_case_id};
					if ($path !~ /compass/) {
						$sth_write_cases->execute($partial_case_id, "partial_matched", $case_name, $patient_id);
					}
				}
				else {
					if ($partial_processed_case_id ne '' ) {
						#print PARTIAL_PROCESSED "$patient_id\t$case_name\t$partial_processed_case_id\n";
						$sth_write_cases->execute($partial_processed_case_id, "partial_processed", $case_name, $patient_id);
					} else {
						#print NOTMATCH "$patient_id\t$case_name\n";
						$sth_write_cases->execute("", "not_matched", $case_name, $patient_id);
					}
				}
			}

		}
	}
}
#close(PERFECT_MATCH);
#close(PARTIAL_MATCH);
#close(NOTMATCH);
#close(NOT_PIPELINE);
#close(PARTIAL_PROCESSED);
#close(NEW_PATIENT);
$dbh->do("update sample_case_mapping s set case_id=case_name, match_type='matched case_name' where exists(select * from processed_cases v where s.patient_id=v.patient_id and v.case_id=s.case_name) and case_id is null");
$dbh->do("update sample_case_mapping s set case_id='', match_type='not_matched' where exists(select * from processed_cases p where s.patient_id=p.patient_id and s.case_id=p.case_id and p.path like 'compass%') and case_id <> case_name");
$dbh->commit();


#open(ORPHAN_CASE, ">orphan_cases.txt");
#$sth_orphan_cases->execute();
#while (my ($patient_id, $case_id, $path) = $sth_orphan_cases->fetchrow_array) {
#	print ORPHAN_CASE "$patient_id\t$case_id\t$path\n";
#}
#$sth_orphan_cases->finish;
#close(ORPHAN_CASE);

$dbh->disconnect();

system("perl $script_dir/refreshViews.pl -p");

