#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $patient_id;
my $case_id;
my $path="processed_DATA";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -p  <integer> patient id
  -c  <string>  case_id
  -t  <string>  path (default $path)
  
__EOUSAGE__
my $r_path = getConfig("R_PATH");
$ENV{'PATH'}=$r_path.$ENV{'PATH'};#Ubuntu16
$ENV{'R_LIBS'}=getConfig("R_LIBS");#Ubuntu16

GetOptions (
  'p=s' => \$patient_id,
  'c=s' => \$case_id,
  't=s' => \$path
);

my $script_dir = abs_path(dirname(__FILE__));
my $data_dir = abs_path($script_dir."/../../../storage/ProcessedResults");
my $batch_home = abs_path($script_dir."/../../../storage/batch_home");
#my $data_dir = "/mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/storage/ProcessedResults";
my $annotation_file = abs_path($script_dir."/../../ref/RSEM/gencode.v36lift37.annotation.txt");

if (!$patient_id || !$case_id) {
	die "Some parameters are missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

my $sql_smp = "select sample_id, sample_name, run_id from samples where sample_id=? or sample_name=?";
my $sql_smp_dtl = "select sample_id, attr_name, attr_value from sample_details where sample_id=? and attr_name in ('ControlGroup','SampleGroup')";

my $sth_smp = $dbh->prepare($sql_smp);
my $sth_smp_dtl = $dbh->prepare($sql_smp_dtl);

my %sample_id_mapping = ();
my %sample_alias_mapping = ();
my %sample_id_alias_mapping = ();
print_log("looking for $data_dir/$path/$patient_id/$case_id/*/RSEM*/*.rsem_ENS.genes.results");
my @rsems = grep { -f } glob "$data_dir/$path/$patient_id/$case_id/*/RSEM*/*.rsem_ENS.genes.results";
if ($#rsems < 1) {
	print_log("No multiple samples found.");
	exit(0);
}
system("mkdir -p $data_dir/$path/$patient_id/$case_id/analysis");
my $analysis_dir = "$data_dir/$path/$patient_id/$case_id/analysis/expression";
#system("rm -rf $analysis_dir");
system("mkdir -p $analysis_dir");
open(META, ">$analysis_dir/meta.txt");
print META "SampleID\tSampleName\tRunID\tSampleGroup\tControlGroup\tFile\n";
foreach my $rsem (@rsems) {
	my $rsem_dir = basename($rsem, ".rsem_ENS.genes.results");
	$sth_smp->execute($rsem_dir, $rsem_dir);
	my ($sample_id, $sample_name, $run_id) = $sth_smp->fetchrow_array;
	my $sample_group = "Unknown";
	my $control_group = "Unknown";
	if ($sample_id) {
		$sth_smp_dtl->execute($sample_id);
		while (my ($sample_id, $attr_name, $attr_value) = $sth_smp_dtl->fetchrow_array) {
			$attr_value =~ s/^\s+|\s+$//;
			$attr_value = "Unknown" if ($attr_value eq "");			
			$control_group = $attr_value if ($attr_name eq 'ControlGroup');
			$sample_group = $attr_value if ($attr_name eq 'SampleGroup');				
		}
		$sth_smp->finish();
		print META "$sample_id\t$sample_name\t$run_id\t$sample_group\t$control_group\t$rsem\n";
	}	
}

$dbh->disconnect();
print_log("Running DESEQ2...");
system("rm -f $analysis_dir/GSEA*.txt");
system("rm -rf $analysis_dir/DE");
system("Rscript $script_dir/caseExpressionAnalysis.r $analysis_dir/meta.txt $annotation_file $analysis_dir");
system("chmod -R g+w $analysis_dir");
my @rnks = grep { -f } glob "$analysis_dir/*.rnk";
#system("rm -rf *.gmt");
foreach my $rnk (@rnks) {
	my $rnk_base = basename($rnk, ".rnk");
	my $gsea_cmd = "sbatch -o ${batch_home}/app/scripts/slurm_log/CaseExpression.$patient_id.$case_id.$rnk_base.o -e ${batch_home}/app/scripts/slurm_log/CaseExpression.$patient_id.$case_id.$rnk_base.e ${batch_home}/app/scripts/backend/runGSEAPrerank.sh $rnk $analysis_dir/";
	print_log("$gsea_cmd");
	#system($gsea_cmd);
}

my @exps = grep { -f } glob "$analysis_dir/*_vs_*.txt";
foreach my $exp (@exps) {
	my $contrast = basename($exp, ".txt");
	my $cls_file = $contrast.".cls";
	$contrast =~ s/_vs_/_versus_/;
	my $gsea_cmd = "sbatch -o ${batch_home}/app/scripts/slurm_log/CaseExpression.$patient_id.$case_id.$contrast.o -e ${batch_home}/app/scripts/slurm_log/CaseExpression.$patient_id.$case_id.$contrast.e ${batch_home}/app/scripts/backend/runGSEA.sh $exp $analysis_dir/${cls_file} $contrast $analysis_dir/";
	print_log("$gsea_cmd");
	system($gsea_cmd);

}

print_log("Done.");