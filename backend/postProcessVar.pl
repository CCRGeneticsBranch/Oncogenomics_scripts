#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;

my $patient_id;
my $case_id;
my $type;
my $hotspot_file = "/mnt/webrepo/fr-s-bsg-onc-d/htdocs/sandbox1/app/storage/data/hg19_Hotspot.01.25.16.txt";
#my $hotspot_predicted = "MSKCC.470sites_clean.txt";
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -p  <string>  Patient ID
  -c  <string>  Case ID
  -t  <string>  Type
  
__EOUSAGE__



GetOptions (
  'p=s' => \$patient_id,
  'c=s' => \$case_id,
  't=s' => \$type
);

unless ($patient_id && $case_id && $type ) {
	print "\nParameters missing\n$usage\n";
	exit;
}
my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,
    LongReadLen => 66000,
    LongTruncOk => 1
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);

my $sth_gene_list = $dbh->prepare("select list_name, gene_list from user_gene_list");

#get gene list
$sth_gene_list->execute();
my %gcgensus = ();
my %combined = ();
while (my ($list_name, $gene_list) = $sth_gene_list->fetchrow_array) {
	if (lc($list_name) eq "cgcensus_hereditary") {
		my @genes = split(/\s+/, $gene_list);
		foreach my $gene (@genes) {
			$gcgensus{$gene} = '';
		}
	}
	if (lc($list_name) eq "combined_gene_list") {
		my @genes = split(/\s+/, $gene_list);
		foreach my $gene (@genes) {
			$combined{$gene} = '';
		}
	}	
}
$sth_gene_list->finish;

#get hotspot site
open(FILE, $hotspot_file) or die "Cannot open file $hotspot_file";
my %hotspot_list = ();
while(<FILE>) {
	chomp;
	my @fields = split(/\t/);
	$hotspot_list{$fields[3]}{$fields[0]}{$fields[1]}{$fields[2]} = $fields[5];	
}
close(FILE);

#get all variants
my $sql = "select distinct v.patient_id, v.case_id, v.type, v.chromosome, v.start_pos, v.end_pos, v.ref, v.alt, 
							a.gene, a.aachange, a.exonicfunc, a.func, a.reported_mutations, v.vaf, v.total_cov, v.vaf_ratio, a.frequency, a.clinvar_clisig, a.hgmd_cat, a.acmg
					from var_annotation a, var_patients v
				where
				v.patient_id='$patient_id' and
				v.case_id ='$case_id' and
				v.type ='$type' and
				a.chromosome=v.chromosome and
				a.start_pos=v.start_pos and
				a.end_pos=v.end_pos and
				a.ref=v.ref and
				a.alt=v.alt";
#print "$sql\n";
my $sth_var = $dbh->prepare($sql);
my $sth_tier = $dbh->prepare("insert into var_tier values(?,?,?,?,?,?,?,?,?,?)");
my %var_germline = ();
my %var_somatic = ();

$sth_var->execute();
while (my ($patient_id, $case_id, $type, $chromosome, $start_pos, $end_pos, $ref, $alt, $gene, $aachange, $exonic_func, $func, $reported_mutations, $vaf, $total_cov, $vaf_ratio, $frequency, $clinvar_clisig, $hgmd_cat, $acmg) = $sth_var->fetchrow_array) {
	my $key = join("\t",$chromosome, $start_pos, $end_pos, $ref, $alt);
	my $combined_gene_list = "";
	my $cgcensus_hereditary = "";
	$frequency = 0 if (!defined $frequency);
	$reported_mutations = 0 if (!defined $reported_mutations);
	$clinvar_clisig = "" if (!defined $clinvar_clisig);
	$hgmd_cat = "" if (!defined $hgmd_cat);
	$acmg = "" if (!defined $acmg);
	$exonic_func = "" if (!defined $exonic_func);


	if (exists $combined{$gene}) {
		$combined_gene_list = "Y";
	}
	if (exists $gcgensus{$gene}) {
		$cgcensus_hereditary = "Y";
	}
	my $loss_func = "";
	#if ($var->func == "splicing" || $var->exonicfunc == "stopgain" || substr($var->exonicfunc, 0, 10) == "frameshift" || $var->exonicfunc == "nonframeshift insertion" || $var->exonicfunc == "nonframeshift deletion" )
	if ($func eq "splicing" || $exonic_func eq "stopgain" || $exonic_func =~ /^frameshift/ || $exonic_func eq "nonframeshift insertion" || $exonic_func eq "nonframeshift deletion") {
		$loss_func = "Y";
	}
	my $actionable_hotspots = "";
	if (exists $hotspot_list{$gene}{$chromosome}{$start_pos}{$end_pos}) {
		$actionable_hotspots = "Y";
	}	

	my $somatic_tier = ($type ne "germline")? &getTier($type, 'somatic', $frequency, $vaf, $gene, $cgcensus_hereditary, $combined_gene_list, $actionable_hotspots, $clinvar_clisig, $hgmd_cat, $acmg, $loss_func, $vaf_ratio, $aachange, $exonic_func, $reported_mutations) : "";
	my $germline_tier = ($type ne "somatic")? &getTier($type, 'germline', $frequency, $vaf, $gene, $cgcensus_hereditary, $combined_gene_list, $actionable_hotspots, $clinvar_clisig, $hgmd_cat, $acmg, $loss_func, $vaf_ratio, $aachange, $exonic_func, $reported_mutations) : "";

	#if ($germline_tier ne "" || $somatic_tier ne "") {
	#if ($gene eq "HIF1A"){
	#$dbh->do("update var_patients set somatic_level='$somatic_tier', germline_level='$germline_tier' where chromosome = '$chromosome' and start_pos = '$start_pos' and end_pos = '$end_pos' and ref = '$ref' and alt = '$alt' and patient_id = '$patient_id' and case_id = '$case_id' and type = '$type'");
	#print "update var_patients set somatic_level='$somatic_tier', germline_level='$germline_tier' where chromosome = '$chromosome' and start_pos = '$start_pos' and end_pos = '$end_pos' and ref = '$ref' and alt = '$alt' and patient_id = '$patient_id' and case_id = '$case_id' and type = '$type'\n";
	#print join("\t", $chromosome, $start_pos, $end_pos, $ref, $alt, $germline_tier, $somatic_tier)."\n";	
	#}
}
$sth_var->finish;
$dbh->commit();
$dbh->disconnect();

sub getTier {
	my ($source, $type, $frequency, $vaf, $gene, $cgcensus_hereditary, $combined_gene_list, $actionable_hotspots, $clinvar_clisig, $hgmd_cat, $acmg, $loss_func, $vaf_ratio, $aachange, $exonic_func, $reported_mutations) = @_;
	#if ($gene eq "TRRAP"){
		#print join("\t", $type, $source, $frequency, $vaf, $gene, $cgcensus_hereditary, $combined_gene_list, $actionable_hotspots, $clinvar_clisig, $hgmd_cat, $acmg, $loss_func, $vaf_ratio, $aachange, $exonic_func)."\n";
		#print join("|", $cgcensus_hereditary, $combined_gene_list, $actionable_hotspots, $clinvar_clisig, $hgmd_cat, $acmg, $loss_func, $vaf_ratio, $aachange, $exonic_func)."\n";
	#}
	if ($frequency > 0.05) {
		return "";
	}
	if ($type eq "germline" && $vaf < 0.25) {
		return "";
	}
	if ($type eq "germline") {
		if ($cgcensus_hereditary ne "" && $clinvar_clisig ne "") {
			return "Tier 1a";
		}
		if ($cgcensus_hereditary ne "" && $hgmd_cat ne "") {
			return "Tier 1b";
		}
		if (($acmg ne '' && $clinvar_clisig ne "") || ($acmg ne '' && $hgmd_cat ne "") || ($actionable_hotspots ne "") || ($combined_gene_list ne "" && $loss_func ne "")) {
			return "Tier 1";
		}
		if ($combined_gene_list ne "" && $clinvar_clisig ne "") {
			return "Tier 1a";
		}
		if ($combined_gene_list ne "" && $hgmd_cat ne "") {
			return "Tier 1b";
		}
		if ($acmg ne "") {
			return "Tier 2";
		}
		if ($cgcensus_hereditary ne '') {
			return "Tier 2";
		}
		if (($hgmd_cat ne "" && $clinvar_clisig ne "") || ($combined_gene_list ne "" && $vaf_ratio >= 1.2 && $source eq "germline")) {
			return "Tier 3";
		}
		if ($hgmd_cat ne "" || $combined_gene_list ne "") {
			return "Tier 4";
		}
	}
	if ($type eq "somatic") {
		#$exonic_func = substr($var->exonicfunc, 0, 13);
		#$aachanges = explode(':',$var->aachange);
		if (($actionable_hotspots ne "") || ($exonic_func =~ /nonframeshift/ && $gene eq "EGFR" && ($aachange =~ /exon19/ || $aachange =~ /exon20/)) || ($exonic_func =~ /nonframeshift/ && $gene eq "BRAF" && $aachange =~ /exon14/)) {
				return "Tier 1.1";
		}
		if ($combined_gene_list ne "" && $reported_mutations >= 5) {
				return "Tier 1.2";
		}
		if (($exonic_func =~ /nonframeshift/ && $gene eq "ERBB2" && $aachange =~ /exon20/) || 
				($exonic_func =~ /nonframeshift/ && $gene eq "KIT" && $aachange =~ /exon11/)) {
				return "Tier 2";
			}
		if ($combined_gene_list ne "") {
			if ($loss_func ne "" || $exonic_func =~ /nonframeshift/) {
				return "Tier 2";
			}
			else {
				return "Tier 3";
			}
		}
		return "Tier 4";
	}
	return "";
}
