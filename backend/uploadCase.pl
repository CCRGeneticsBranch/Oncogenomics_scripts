#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use LWP::Simple;
use LWP::UserAgent;
use Scalar::Util qw(looks_like_number);
use Try::Tiny;
use MIME::Lite; 
use File::Temp qw/ tempfile tempdir /;
use POSIX;
use Cwd 'abs_path';
use Time::Piece;
require(dirname(abs_path($0))."/../lib/Onco.pm");

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		#die "Warning:$message";
		print_log("Warning:$message");
	}
};
my ($host, $sid, $username, $passwd, $port) = getDBConfig();

my $script_dir = abs_path(dirname(__FILE__));
my $app_path = abs_path($script_dir."/../../..");

my $target_patient;
my $target_case;
my $url = getConfig("URL");
my $url_production = getConfig("URL_PRODUCTION");
my $web_user = getConfig("WEB_USER");
my $conda_path = getConfig("CONDA_PATH");
my $reconCNV_path = getConfig("RECONCNV_PATH");
my $aws = getConfig("AWS");
my $db_name = "development";
my $update_list_file;
my $skip_fusion = 0;
my $replaced_old = 0;
my $insert_col = 0;
my $load_type = "all";
my $use_sqlldr = 0;
my $remove_noncoding = 0;
my $refresh_exp = 0;
my $case_name_eq_id = 0;
my $email = getConfig("EMAILS");
my $dev_email = getConfig("DEV_EMAILS");
my $dir_example = abs_path("$app_path/storage/ProcessedResults/processed_DATA");
my $dir;
my $project_folder_desc;

my $usage = <<__EOUSAGE__;


Usage:

$0 [options]

Options:

  -i  <string>  Input folder (example: $dir_example) 
  -o  <string>  Folder description
  -l  <string>  Update list  
  -u  <string>  Oncogenomic url (default: $url)
  -d  <string>  Database name (default: $db_name)
  -r            Replace old data
  -s            Use SQLLoader
  -p  <string>  Upload specified patient
  -c  <string>  Upload specified case
  -a            Append annotation column table
  -g            Remove noncoding variants (annotated by AVIA)
  -t  <string>  Load type: (all,fusion,variants,tier,annotation,qc,cnv,antigen,exp,burden,genotyping,tcell_extrect,qci,mixcr), default: $load_type
  -x            Update expression data
  -k            Assign case id using case name.
  -y            Skip loading fusion
  -e  <string>  Email be notified.
  
__EOUSAGE__



GetOptions (
  'i=s' => \$dir,
  'o=s' => \$project_folder_desc,
  'u=s' => \$url,
  'd=s' => \$db_name,
  'l=s' => \$update_list_file,
  'r' => \$replaced_old,
  's' => \$use_sqlldr,
  'g' => \$remove_noncoding,
  'a' => \$insert_col,
  'x' => \$refresh_exp,  
  'p=s' => \$target_patient,
  'c=s' => \$target_case,
  't=s' => \$load_type,
  'k' => \$case_name_eq_id,
  'y' => \$skip_fusion,
  'e=s' => \$email
);

if (!$dir || (!$update_list_file && !$target_patient)) {
    die "Some parameters are missing\n$usage";
}

#$dir = "/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults/$dir";

if (!$update_list_file) {
	$update_list_file = '';
	#$replaced_old = 1;
}


my $dbh = getDBI();
my $db_type = getDBType();
#$dbh->trace(4);

chdir $dir;

my $var_sample_tbl = "var_samples";
my $var_annotation_tbl = "var_annotation";
my $var_annotation_col_tbl = "var_annotation_col";
my $var_annotation_dtl_tbl = "var_annotation_details";
#my $sth_ano_exists = $dbh->prepare("select count(*) from $var_annotation_tbl where chromosome = ? and start_pos = ? and end_pos = ? and ref = ? and alt = ?");
my $sth_diag = $dbh->prepare("select diagnosis from patients where patient_id=?");
my $sth_emails = $dbh->prepare("select email_address from users where permissions like '%_superadmin%'");
my $sth_fu = $dbh->prepare("insert into var_fusion values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_smp = $dbh->prepare("insert into $var_sample_tbl values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_splice = $dbh->prepare("insert into var_splicing values (?,?,?,?,?,?,?,?,?,?,?,?)");
#my $sth_ano = $dbh->prepare("insert into $annotation_tbl values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
#my $sth_ano = $dbh->prepare("insert into $var_annotation_tbl values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
#my $sth_ano_dtl = $dbh->prepare("insert into $var_annotation_dtl_tbl values(?,?,?,?,?,?,?,?)");
#my $sth_ano_col = $dbh->prepare("insert into $var_annotation_col_tbl values(?,?,?)");
#my $sth_act = $dbh->prepare("insert into var_actionable_site values(?,?,?,?,?,?,?,?,?,?)");
my $sth_qc = $dbh->prepare("insert into var_qc values(?,?,?,?,?,?)");
my $sth_exp = $dbh->prepare("insert into /*+ APPEND */ sample_values values(?,?,?,?,?,?,?)");
#my $sth_tier = $dbh->prepare("insert into /*+ APPEND */ var_tier values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_sample_cases = $dbh->prepare("update sample_cases set case_id=? where patient_id=? and case_id=?");
my $sth_tier_avia = $dbh->prepare("insert into /*+ APPEND */ var_tier_avia values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_var_qci = $dbh->prepare("insert /*+ APPEND */ into var_qci values(?,?,?,?,?,?,?,?,?)");
my $sth_var_qci_annotation = $dbh->prepare("insert /*+ APPEND */ into var_qci_annotation values(?,?,?,?,?,?,?,?,?,?,?)");
my $sth_var_qci_summary = $dbh->prepare("insert /*+ APPEND */ into var_qci_summary values(?,?,?,?,?)");
my $sth_cnv = $dbh->prepare("insert into var_cnv values(?,?,?,?,?,?,?,?,?,?)");
my $sth_cnv_segment = $dbh->prepare("insert into var_cnv_segment values(?,?,?,?,?,?,?,?,?,?,?)");
my $sth_cnv_gene = $dbh->prepare("insert into var_cnv_gene_level values(?,?,?,?,?,?,?,?,?,?)");
my $sth_cnvkit = $dbh->prepare("insert into var_cnvkit values(?,?,?,?,?,?,?,?,?,?)");
my $sth_cnvkit_segment = $dbh->prepare("insert into var_cnvkit_segment values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_cnvkit_gene = $dbh->prepare("insert into var_cnvkit_gene_level values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_cnvtso = $dbh->prepare("insert into var_cnvtso values(?,?,?,?,?,?,?,?,?)");
my $sth_tcell_extrect = $dbh->prepare("insert into tcell_extrect values(?,?,?,?,?,?,?)");
my $sth_mutation_burden = $dbh->prepare("insert into mutation_burden values(?,?,?,?,?,?)");
my $sth_mixcr_summary = $dbh->prepare("insert into mixcr_summary values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_mixcr = $dbh->prepare("insert into mixcr values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_neo_antigen = $dbh->prepare("insert into neo_antigen values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
my $sth_hla = $dbh->prepare("insert into hla values(?,?,?,?,?,?)");
my $stn_del_noncoding = $dbh->prepare("delete from $var_sample_tbl v where patient_id=? and case_id=? and exists(select * from hg19_annot\@pub_lnk a where SUBSTR(v.chromosome,4) = a.chr and v.start_pos=a.query_start and v.end_pos=a.query_end and v.ref=a.allele1 and v.alt=a.allele2 and (maf > 0.05 or annovar_annot not in ('exonic','splicing','exonic;splicing')))");
my $stn_rnaseqfp_avia = $dbh->prepare("delete from var_tier_avia t where type='rnaseq' and exists(select * from rnaseq_fp r where t.chromosome=r.chromosome and t.start_pos=r.start_pos and t.end_pos=r.end_pos and t.ref=r.ref and t.alt=r.alt)");

my $sth_update_smp_exp_cov = $dbh->prepare("update $var_sample_tbl v1 
	set (matched_var_cov, matched_total_cov) = (select var_cov, total_cov from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type='rnaseq' and
	  rownum=1
	  )
	where patient_id=? and case_id=? and type <> 'somatic' and type <> 'rnaseq' and type <> 'hotspot' and exists(select * from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type='rnaseq')");

my $sth_update_smp_dna_cov = $dbh->prepare("update $var_sample_tbl v1 
	set (matched_var_cov, matched_total_cov) = (select var_cov, total_cov from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type<>'rnaseq' and
	  rownum=1
	  )
	where patient_id=? and case_id=? and type='rnaseq' and exists(select * from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type<>'rnaseq')");

my $sth_update_smp_hotspot_exp_cov = $dbh->prepare("update $var_sample_tbl v1 
	set (matched_var_cov, matched_total_cov) = (select var_cov, total_cov from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type='hotspot' and
	  v2.exp_type='RNAseq' and
	  rownum=1
	  )
	where patient_id=? and case_id=? and type='hotspot' and exp_type <> 'RNAseq' and exists(select * from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type='hotspot' and
	  v2.exp_type='RNAseq')");

my $sth_update_smp_hotspot_dna_cov = $dbh->prepare("update $var_sample_tbl v1 
	set (matched_var_cov, matched_total_cov) = (select var_cov, total_cov from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type='hotspot' and
	  v2.exp_type<>'RNAseq' and	  
	  rownum=1
	  )
	where patient_id=? and case_id=? and type='hotspot' and exp_type='RNAseq' and exists(select * from $var_sample_tbl v2 where
	  v1.chromosome=v2.chromosome and
	  v1.start_pos=v2.start_pos and
	  v1.end_pos=v2.end_pos and
	  v1.ref=v2.ref and
	  v1.alt=v2.alt and
	  v1.patient_id=v2.patient_id and
	  v1.case_id=v2.case_id and
	  v2.type='hotspot' and
	  v2.exp_type<>'RNAseq'
	  )");

$dir = &formatDir($dir);

my $project_folder = basename($dir);

my %update_list = ();
my %update_cases = ();

my %var_smp = ();
my %failed_data = ();

if ($update_list_file ne '') {
	open(UPDATE_FILE, $update_list_file) or die "Cannot open file $update_list_file";
	while(<UPDATE_FILE>) {
		chomp;
		$update_list{$_} = '';
		if (/(.*?)\/(.*?)\/successful.txt/) {
			my $failed = $dir."$1/$2/failed.txt";
			system("rm -rf $failed");
			$update_cases{$1}{$2} = '';
		}
		if (/(.*?)\/(.*?)\/failed_delete.txt/) {
			my $diagnosis = &getDiagnosis($1);
			system("perl $script_dir/deleteCase.pl -p $1 -c $2 -r -b -t $project_folder");
			my $patient_key = "$1\t$2\t$diagnosis";
			$failed_data{$patient_key} = '';
		}
	}
	close(UPDATE_FILE);
} 

my %var_anno = ();

# get sample information
my $sth_smp_cat = $dbh->prepare("select sample_id, sample_name, tissue_cat, exp_type, relation, normal_sample, rnaseq_sample, sample_alias from samples");
$sth_smp_cat->execute();
my %sample_type = ();
my %sample_alias = ();
my %sample_names = ();
my %sample_exp_type = ();
my %sample_relation = ();
my %match_normal = ();
my %match_tumor = ();
my %match_rnaseq = ();
my %chr_list = ();

for (my $i=1; $i<=22; $i++) {
	$chr_list{"chr".$i} = '';
}
$chr_list{"chrX"} = '';
$chr_list{"chrY"} = '';

while (my @row = $sth_smp_cat->fetchrow_array) {
	next if (!$row[0]);
	$sample_type{$row[0]} = $row[2];
	$sample_alias{$row[7]} = $row[0] if ($row[7]);
	$sample_names{$row[0]} = $row[1];
	$sample_exp_type{$row[0]} = $row[3];
	$sample_relation{$row[0]} = $row[4];
	if ($row[5]) {
		if ($row[0] ne $row[5] && $row[1] ne $row[5]) {
			$match_normal{$row[0]} = $row[5];
		}
	}
	$match_rnaseq{$row[0]} = $row[6] if ($row[6]);
}
$sth_smp_cat->finish;

while (my ($sample_id, $normal_id) = each %match_normal) {
	if (exists $sample_alias{$normal_id}) {
		$normal_id = $sample_alias{$normal_id};
		$match_normal{$sample_id} = $normal_id;
	}
	push @{$match_tumor{$normal_id}}, $sample_id;
}
while (my ($sample_id, $rnaseq_id) = each %match_rnaseq) {
	if (exists $sample_alias{$rnaseq_id}) {
		$match_rnaseq{$sample_id} = $sample_alias{$rnaseq_id};
	}
}

#get all cases

my $sth_cases = $dbh->prepare("select * from var_type");
$sth_cases->execute();
my %cases = ();
while (my @row = $sth_cases->fetchrow_array) {
	$cases{$row[0].$row[1].$row[2]} = $row[3];
}
$sth_cases->finish;

my %fusion_data = ();
my %coding_genes = ();

#get gene/transcripts id mapping
my %symbol_mapping = ();
my %gene_mapping = ();

my $sth_genes = $dbh->prepare("select symbol,gene from gene");
$sth_genes->execute();
while (my ($symbol,$gene) = $sth_genes->fetchrow_array) {
	$gene_mapping{$gene} = $gene;
	$symbol_mapping{$gene} = $symbol;
}
$sth_genes->finish;

my @patient_dirs = grep { -d } glob $dir."*";
my %new_data = ();
my @errors = ();
#print "use sqlldr? ($use_sqlldr)...load type = $load_type\n";
foreach my $patient_dir (@patient_dirs) {
	my $patient_id = basename($patient_dir);
	my $diagnosis = &getDiagnosis($patient_id);
	$patient_dir = &formatDir($patient_dir);
	if ($target_patient) {
		next if ($patient_id ne $target_patient);
	}	
	#print "Processing patient: ($project_folder) $patient_id $sid\n";
	my @case_dirs = grep { -d } glob $patient_dir."*";
	foreach my $case_dir (@case_dirs) {
		my $case_id = basename($case_dir);
		if ($target_case) {
			next if ($case_id ne $target_case);
		}
		
		$case_dir = &formatDir($case_dir);
		my $succss_file = $dir."$patient_id/$case_id/successful.txt";
		my $failed_file = $dir."$patient_id/$case_id/failed.txt";
		my $failed_file_del = $dir."$patient_id/$case_id/failed_delete.txt";
		my $status = ($project_folder eq "clinomics")? 'pending' : 'passed';
# Note to other developers from Hue:  If this script (loadVarPatients.pl) is run on prod first (which it is), it will have already deleted the directory $patient_id/$case_id
#...when it gets to this step in dev, the $patient_id/$case_id/failed.txt or failed_delete.txt will no longer exist and WILL NOT run deleteCase.pl
# This means that the dev script will not delete orphan data in the database because it needs the presence of this directory on server 
# Noticed this because the development database had a lot of legacy data from previous cases
# Hue changed this from "if ( -e $failed_file && $load_type ne 'tier') { "
# to next line on 20190820
		if ( ($db_name=~/dev/ && -e $failed_file) && $load_type ne 'tier') {
			system("perl $script_dir/deleteCase.pl -p $patient_id -c $case_id") ;
			my $patient_key = "$patient_id\t$case_id\t$diagnosis";
			#print "FAILED $failed_file\n";
			$failed_data{$patient_key} = '';
			next;
		}
		if (-e $failed_file_del && $load_type ne 'tier') {
			print_log("Removing case $patient_id/$case_id");
			system("perl $script_dir/deleteCase.pl -p $patient_id -c $case_id -r");
			my $patient_key = "$patient_id\t$case_id\t$diagnosis";
			$failed_data{$patient_key} = '';
			next;
		}

		if ($update_list_file ne '') {
			next if (!exists $update_cases{$patient_id}{$case_id});			
			#if ($project_folder eq "clinomics") {
				next unless (-e $succss_file);				
			#}
		}

		print_log("processing case: $patient_id/$case_id");
		my $start = time;

		#my $last_mod_time = (stat ($succss_file))[9];
		#print "file: $succss_file\n";
		if ($load_type eq "all" || $load_type eq "version") {
			my $last_mod_time = POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime(( stat "$dir$patient_id/$case_id" )[9]));
			if (-e $succss_file) {
				$last_mod_time = POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime(( stat $succss_file )[9]));
			} else {
				$status = "not_successful";				
			}
			#print "last_mod_time: $last_mod_time\n";
			my $sth_case_exists = $dbh->prepare("select count(*) from processed_cases where patient_id='$patient_id' and case_id='$case_id'");
			$sth_case_exists->execute();
			my @case_row = $sth_case_exists->fetchrow_array;
			my $exists = ($case_row[0] > 0);
			$sth_case_exists->finish;
			my $case_name = '';
			if ($case_name_eq_id) {
				$case_name = $case_id;
			}

			my @version_ret = readpipe("$script_dir/getPipelineVersion.sh $case_dir");
			my $version = "NA";
			if ($#version_ret >= 0) {
				$version = $version_ret[0];
			}
			chomp $version;	
			my @genome_version_ret = readpipe("$script_dir/getPipelineGenomeVersion.sh $case_dir");
			my $genome_version = "hg19";
			if ($#genome_version_ret >= 0) {
				$genome_version = $genome_version_ret[0];
			}
			chomp $genome_version;
			my $convert_time_fun = "TO_TIMESTAMP";
			my $date_format = "YYYY-MM-DD HH24:MI:SS";
			if ($db_type eq "mysql") {
				$convert_time_fun = "STR_TO_DATE";
				$date_format = "%Y-%m-%d %H:%i:%i";
			}		
			
			my $sql = "insert into processed_cases values('$patient_id', '$case_id', '$project_folder', '$status', $convert_time_fun('$last_mod_time', '$date_format'), CURRENT_TIMESTAMP,CURRENT_TIMESTAMP, '$version', '$genome_version')";
			if ($exists) {					
				$sql = "update processed_cases set genome_version='$genome_version', version='$version', status='$status', finished_at=$convert_time_fun('$last_mod_time', '$date_format'), updated_at=CURRENT_TIMESTAMP where patient_id='$patient_id' and case_id='$case_id'";
			}
			#print "$sql\n";
			#print "\tinserted into or updated time in CASES table..\n";
			$dbh->do($sql);		
			$dbh->commit();			
		}
		
		my $link_url = $url;
		if ($db_name eq "production") {
			$link_url = $url_production;
		}
		my $patient_link = "<a target=_blank href='$link_url/viewPatient/any/$patient_id'>$patient_id</a>";
		my $patient_key = "$patient_link\t$case_id\t$diagnosis";

		#process fusion		
		my $fusion_file = "$patient_id/$case_id/Actionable/$patient_id.fusion.actionable.txt";
		#print("fusion file: $fusion_file\n");
		#if (-e $dir.$fusion_file && ($replaced_old || exists $update_list{$fusion_file})) {
		if (-e $dir.$fusion_file) {
				#print("fusion file exists\n");
				if (($load_type eq "all" || $load_type eq "fusion" ) && !$skip_fusion) {
						my $new_fusion_file = "$dir$patient_id/$case_id/$patient_id/db/${patient_id}.fusion.txt";
						#print($new_fusion_file."\n");
						my $fusion_output_file = "$dir$patient_id/$case_id/$patient_id/db/var_fusion.tsv";
						my $fusion_detail_output_file = "$dir$patient_id/$case_id/$patient_id/db/var_fusion_details.tsv";
						
						if ( -e $new_fusion_file || $replaced_old ) {
								try {
									print_log("processing fusion $new_fusion_file");
									&insertNewFusion($case_id, $patient_id, $new_fusion_file, $project_folder);
								} catch {
									print_log("errors in fusion: $_");
									push(@errors, "$patient_id\t$case_id\tFusion\t$_");
								};
						}
						$new_data{$patient_key}{"fusion"} = '';
				}
		}		

		#process variants
		my @files = grep { -f } glob $case_dir."$patient_id/db/*";

		my $sample_file = "$dir$patient_id/$case_id/$patient_id/db/var_samples.tsv";
		my $tier_file = "$dir$patient_id/$case_id/$patient_id/db/var_tier.tsv";
		my $tier_avia_file = "$dir$patient_id/$case_id/$patient_id/db/var_tier_avia.tsv";
		if ($use_sqlldr) {
			system("rm -f $sample_file");
			system("rm -f $tier_file");
			system("rm -f $tier_avia_file");
		}
		
		if ($load_type eq "all" || $load_type eq "variants") {
			#print "deleting from $var_sample_tbl (case_id='$case_id' and patient_id='$patient_id')\n";
			$dbh->do("delete from $var_sample_tbl where case_id='$case_id' and patient_id='$patient_id'");
			if (!$replaced_old && $use_sqlldr) {
				print "commiting $var_sample_tbl\n";
				$dbh->commit();
			}
		}

		#if ($load_type eq "all" || $load_type eq "tier") { #testing tiering 2/14/19	
		if ($load_type eq "tier") { 
			$dbh->do("delete from var_tier_avia where case_id='$case_id' and patient_id='$patient_id'"); #<-----NEW ON 2/7/2018, why delete from var_tier and not var_tier_avia
			if (!$replaced_old && $use_sqlldr) {
				print_log("commiting tiering");
				$dbh->commit();
			}			
		}

		if ($load_type eq "all" || $load_type eq "qci") {
			$dbh->do("delete from var_qci_annotation where case_id = '$case_id' and patient_id = '$patient_id'");
			$dbh->do("delete from var_qci_summary where case_id = '$case_id' and patient_id = '$patient_id'");
		}

		foreach my $file (@files) {
			if ($file =~ /QCI-final.txt/ || $file =~ /.qci.txt/) {
					if ($load_type eq "all" || $load_type eq "qci") {
						try {	
								&insertQCI($case_id, $patient_id, $file);
						} catch {
							print_log("insert QCI error $_");
							push(@errors, "$patient_id\t$case_id\tQCI\t$_");
						}
					}
			}
			if ($file =~ /.*\.(germline|somatic|rnaseq|variants|hotspot|splice)$/) {
				my $type = $1;				
				my $db_file = "$patient_id/$case_id/$patient_id/db/$patient_id.$type";
				if (-e $dir.$db_file) {
					next if ($type ne "rnaseq" && ($patient_id eq "ASPS018" || $patient_id eq "ASPS019"));					
					if ($load_type eq "all" || $load_type eq "variants") {
						try {	
							#print "inserting $type, $case_id, $patient_id\n";
							if ($type eq "splice") {
								&insertSplice($case_id, $patient_id, $dir.$db_file, $project_folder);
							} else {
								&insertSample($type, $case_id, $patient_id, $dir.$db_file, $project_folder, $sample_file);
							}
						} catch {
							push(@errors, "$patient_id\t$case_id\tVariants-$type\t$_");
						};						
						$new_data{$patient_key}{$type} = '';
						#system("$script_dir/postProcessVar.pl -p $patient_id -c $case_id -t $type");
					}
					next if ($type eq "hotspot");
					if ($load_type eq "tier") { #testing tiering 2/14/19
					#if ($load_type eq "tier") {
						#print "running $file for $patient_id\n";
						try {
							my $sql = "select distinct sample_id from var_samples where patient_id='$patient_id' and case_id='$case_id' and type= '$type'";
							#print "$sql\n";
							my $sth_samples = $dbh->prepare($sql);
							$sth_samples->execute();
							while (my @row = $sth_samples->fetchrow_array) {
								my $sample_id = $row[0];
								&insertTier($type, $case_id, $patient_id, $sample_id, $tier_file, $tier_avia_file);
							}
							$sth_samples->finish;
							
						} catch {
							push(@errors, "$patient_id\t$case_id\tTier-$type\t$_");
						};
						$new_data{$patient_key}{'tier'} = '';
					}
				}				
			}
		}		
		if ($load_type eq "all" || $load_type eq "variants" || $load_type eq "vcf") {			
			if ($use_sqlldr) {
				my $ret = &callSqlldr($sample_file, $script_dir."/ctrl_files/var_samples.ctrl");
				if ($ret ne "ok") {
					push(@errors, "$patient_id\t$case_id\tVariants\tSQLLoader");
				}
			}
			if (!-e "$dir$patient_id/$case_id/$patient_id.$case_id.vcf.zip" || $replaced_old) {
				print_log("making vcf zip files...$dir$patient_id/$case_id/$patient_id.$case_id.vcf.zip");
				system("rm -rf ./$patient_id/$case_id/$patient_id.$case_id.vcf.zip");
				my $cmd = "zip ./$patient_id/$case_id/$patient_id.$case_id.vcf.zip ./$patient_id/$case_id/*/calls/*.snpEff.vcf";
				if ( glob("$dir$patient_id/$case_id/*/calls/*.snpEff.vcf")) {
					system($cmd);
				}
			}
			if ($remove_noncoding) {
				$stn_del_noncoding->execute($patient_id, $case_id);
			}
			
			#update expression coverage			
			#$sth_update_pat_exp_cov->execute($patient_id, $case_id);
			
			#$sth_update_smp_dna_cov->execute($patient_id, $case_id);
			#$sth_update_smp_exp_cov->execute($patient_id, $case_id);
			#$sth_update_smp_hotspot_dna_cov->execute($patient_id, $case_id);
			#$sth_update_smp_hotspot_exp_cov->execute($patient_id, $case_id);			
			#$sth_update_pat_dna_cov->execute($patient_id, $case_id);
			
			#$sth_delete_smp_rnaseq_splicing->execute($patient_id, $case_id); #<------------------DELETING SPLICE VARIANTS
			#$sth_delete_pat_rnaseq_splicing->execute($patient_id, $case_id);
			$dbh->commit();
		}

		#if ($load_type eq "all" || $load_type eq "tier") { #testing tiering 2/14/19
		if ($load_type eq "tier") {
			if ($use_sqlldr) {
				my $ret = &callSqlldr($tier_file, $script_dir."/ctrl_files/var_tier.ctrl");
				if ($ret ne "ok") {
					push(@errors, "$patient_id\t$case_id\tTier\tSQLLoader");
				}
				$ret = &callSqlldr($tier_avia_file, $script_dir."/ctrl_files/var_tier_avia.ctrl");
				if ($ret ne "ok") {
					push(@errors, "$patient_id\t$case_id\tTier\tSQLLoader");
				}
			}
		}

		#process QC		
		if ($load_type eq "all" || $load_type eq "qc" || $load_type eq "variants") {
			#print ("deleting qc data\n");
			$dbh->do("delete from var_qc where case_id = '$case_id' and patient_id = '$patient_id'");	
		}
		
		my $qc_file = "$patient_id/$case_id/qc/$patient_id.consolidated_QC.txt";
		
		if (-e $dir.$qc_file) {
			if ($load_type eq "all" || $load_type eq "qc" || $load_type eq "variants") {
				try {
					&insertQC($case_id, $patient_id, $dir.$qc_file, "dna");
				} catch {
					push(@errors, "$patient_id\t$case_id\tQC-DNA\t$_");
				};
			}
		}
		#process RNA QC		
		$qc_file = "$patient_id/$case_id/qc/$patient_id.RnaSeqQC.txt";
		if (-e $dir.$qc_file) {
			if ($load_type eq "all" || $load_type eq "qc" || $load_type eq "variants") {
				try {
					&insertQC($case_id, $patient_id, $dir.$qc_file, "rna");
				} catch {
					push(@errors, "$patient_id\t$case_id\tQC-RNA\t$_");
				};
			}
		}
		#process RNA QC	V2

=pod	
		$qc_file = "qc/rnaseqc/metrics.tsv";
		opendir( my $DIR, $dir."$patient_id/$case_id" );
		while ( my $entry = readdir $DIR ) {
    		next unless -d $dir."$patient_id/$case_id" . '/' . $entry;
    		next if $entry eq '.' or $entry eq '..';
    		if(-e $dir."$patient_id/$case_id" . '/' . $entry.'/'.$qc_file){
    			# print $dir."$patient_id/$case_id" . '/' . $entry.'/'.$qc_file."\n";
    			if ($load_type eq "all" || $load_type eq "qc" || $load_type eq "variants") {
					try {
						&insertQC($case_id, $patient_id, $dir."$patient_id/$case_id" . '/' . $entry.'/'.$qc_file, "rnaV2");				
					} catch {
						push(@errors, "$patient_id\t$case_id\tQC-RNAV2\t$_");
					};
				}

    		}
		}
=cut
		my @qc_files = glob "$dir/$patient_id/$case_id/*/qc/*rnaseqc/metrics.tsv";
		foreach my $qc_file(@qc_files) {
			if ($load_type eq "all" || $load_type eq "qc" || $load_type eq "variants") {
					try {
						&insertQC($case_id, $patient_id, $qc_file, "rnaV2");				
					} catch {
						push(@errors, "$patient_id\t$case_id\tQC-RNAV2\t$_");
					};
			}
		}

		#process CNV
		if ($load_type eq "all" || $load_type eq "cnv") {
			my @sample_dirs = grep { -d } glob $case_dir."*";
			my $inserted = 0;
			foreach my $d (@sample_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $ret = &insertCNV($dir, $folder_name, $patient_id, $case_id);					
					my $rettso = &insertCNVTSO500($dir, $folder_name, $patient_id, $case_id);
					if ($ret || $rettso) {
						$inserted = 1;
					}
				} catch {
					print_log("Error in CNV gene: $_");
					push(@errors, "$patient_id\t$case_id\tCNV\t$_");
				};				
			}	
			if ($inserted) {
				$new_data{$patient_key}{'CNV'} = '';
			}
		}

		#process CNV gene level
		if ($load_type eq "all" || $load_type eq "cnv" || $load_type eq "cnvkit") {
			my @sample_dirs = grep { -d } glob $case_dir."*";
			my $inserted = 0;
			foreach my $d (@sample_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $retkit = &insertCNVKit($dir, $folder_name, $patient_id, $case_id);
					my $retkitgene = &insertCNVKitGene($dir, $folder_name, $patient_id, $case_id);					
					if ($retkit || $retkitgene) {
						$inserted = 1;
					}
				} catch {
					print_log("Error in CNV gene: $_");
					push(@errors, "$patient_id\t$case_id\tCNV\t$_");
				};				
			}	
			if ($inserted) {
				$new_data{$patient_key}{'CNV'} = '';
			}
		}		

		#process TCell_Extract
		if ($load_type eq "all" || $load_type eq "tcell_extrect") {
			my @sample_dirs = grep { -d } glob $case_dir."*";
			my $inserted = 0;
			foreach my $d (@sample_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $ret = &insertTCellExTRECT($dir, $folder_name, $patient_id, $case_id);
					if ($ret) {
						$inserted = 1;
					}
				} catch {
					push(@errors, "$patient_id\t$case_id\tTCellExTRECT\t$_");
				};				
			}	
			if ($inserted) {
				$new_data{$patient_key}{'TCellExTRECT'} = '';
			}
		}

		#process Genotyping
		if ($load_type eq "genotyping") {
			my $r_option = "-r";
			print_log("processing genotyping: $script_dir/scorePatientGenotypes.pl -p $patient_id $r_option");
			system("$script_dir/scorePatientGenotypes.pl -p $patient_id $r_option");			
		}

		
		#process neoantigen
		if ($load_type eq "all" || $load_type eq "antigen") {
			my @sample_dirs = grep { -d } glob $case_dir."*";
			my $inserted = 0;
			foreach my $d (@sample_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $ret = &insertNeoAntigen($dir, $folder_name, $patient_id, $case_id);
					if ($ret) {
						$inserted = 1;
					}
				} catch {
					push(@errors, "$patient_id\t$case_id\tNeoAntigen\t$_");
				};				
			}	
			if ($inserted) {
				$new_data{$patient_key}{'antigen'} = '';
			}
		}

		#process HLA
		if ($load_type eq "all" || $load_type eq "hla") {
			my @sample_dirs = grep { -d } glob $case_dir."*";
			my $inserted = 0;
			foreach my $d (@sample_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $ret = &insertHLA($dir, $folder_name, $patient_id, $case_id);
					if ($ret) {
						$inserted = 1;
					}
				} catch {
					push(@errors, "$patient_id\t$case_id\tHLA\t$_");
				};				
			}	
			if ($inserted) {
				$new_data{$patient_key}{'hla'} = '';
			}
		}

		#check Mixcr
		if ($load_type eq "all" || $load_type eq "mixcr") {
			my @mix_dirs = grep { -d } glob $case_dir."*";
			foreach my $d (@mix_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $ret = &insertMixcr($dir, $folder_name, $patient_id, $case_id);
					if ($ret) {
						$new_data{$patient_key}{'mixcr'} = '';
					}
				} catch {
					push(@errors, "$patient_id\t$case_id\tMixcr\t$_");
				};						
			}
		}

		#process mutation burden
		if ($load_type eq "all" || $load_type eq "burden") {
			my @sample_dirs = grep { -d } glob $case_dir."*";
			my $inserted = 0;
			foreach my $d (@sample_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);				
				try {					
					my $ret = &insertBurden($dir, $folder_name, $patient_id, $case_id);
					if ($ret) {
						$inserted = 1;
					}
				} catch {
					push(@errors, "$patient_id\t$case_id\tmutation_burden\t$_");
				};				
			}	
			if ($inserted) {
				$new_data{$patient_key}{'mutation_burden'} = '';
			}
		}

		#for Manoj's RSEM data. Filter out genes not defined in our pipeline
		if ($load_type eq "all") {
			my @exp_dirs = grep { -d } glob $case_dir."*";
			foreach my $d (@exp_dirs) {
				$d = &formatDir($d);
				my $folder_name = basename($d);
				my $rsem_file = $dir.$patient_id."/$case_id/$folder_name/RSEM/$folder_name.rsem.genes.results";
				#print("processing RSEM file $rsem_file\n");
				if (-e $rsem_file) {
					my $rsem_filtered_file = $dir.$patient_id."/$case_id/$folder_name/RSEM/${folder_name}.rsem_ENS.genes.results";
					my $filter_cmd = "perl ${script_dir}/filterRSEM.pl $rsem_file > $rsem_filtered_file";
					#print("$filter_cmd\n");
					system($filter_cmd);
					system("chgrp -f $web_user $rsem_filtered_file;chmod -f 770 $rsem_filtered_file");
				}
			}
		}

		#process expression data
		if ($load_type eq "all") {
			my $exp_cmd = "perl ${script_dir}/caseExpressionAnalysis.pl -p $patient_id -c $case_id -t $project_folder";
			#print("$exp_cmd\n");
			print_log("processing expression analysis");
			system($exp_cmd);
		}
		#next if ($load_type ne "exp" || $refresh_exp);		
		
		my $duration = time - $start;
		print_log("done $patient_id/$case_id");
		#print "Patient $patient_id upload time: $duration seconds\n";
	}
}

$stn_rnaseqfp_avia->execute();

my $subject   = "Oncogenomics $db_name DB upload status ($project_folder)";
my $sender    = 'oncogenomics@mail.nih.gov';
#my $recipient = 'hsien-chao.chou@nih.gov';
my $recipient = $dev_email;
#my $recipient = 'vuonghm@mail.nih.gov';
if ($email ne "" && ($load_type eq "all" || $load_type eq "db")) {
	$recipient = "$email";
}

#print("recipient: $recipient\n");
my $log_cotent = "";
my $failed_cotent = "";
my $err_cotent = "";
my $total_cases = keys %new_data;
print_log("total $total_cases case(s) are uploaded");
my @types = ("germline", "somatic", "variants", "rnaseq", "hotspot", "tier", "fusion", "mixcr", "expression", "CNV", "antigen", "mutation_burden", "TCellExTRECT");
foreach my $patient_key (sort keys %new_data) {	
	$log_cotent .= "<tr>";
	my @fields = split(/\t/, $patient_key);
	foreach my $field (@fields) {
		$log_cotent .= "<td>$field</td>";
	}
	foreach my $type (@types) {
		if (exists $new_data{$patient_key}{$type}) {
			$log_cotent .= "<td>&#10004;</td>";
		} else {
			$log_cotent .= "<td></td>";
		}
	}
	$log_cotent .= "</tr>";
}

foreach my $patient_key (sort keys %failed_data) {
	$failed_cotent .= "<tr>";
	my @fields = split(/\t/, $patient_key);
	foreach my $field (@fields) {
		$failed_cotent .= "<td>$field</td>";
	}
	$failed_cotent .= "</tr>";
}

foreach my $err (@errors) {
	$err_cotent .= "<tr>";
	my @fields = split(/\t/, $err);
	foreach my $field (@fields) {
		$err_cotent .= "<td>$field</td>";
	}
	$err_cotent .= "</tr>";
}

if (!$project_folder_desc) {
	$project_folder_desc = $project_folder;
	if ($project_folder eq "uploads") {
		$project_folder_desc = "";
	}
}
my $data = qq{
	
    <h2>The following <font color=red>$project_folder_desc</font> data has been uploaded to $db_name DB ($total_cases cases):</h2>

    <table id="log" border=1 cellspacing="2" width="60%">
    	<thead><tr><th>Patient ID</th><th>Case ID</th><th>Diagnosis</th><th>Germline</th><th>Somatic</th><th>DNA Variants</th><th>RNASeq Variants</th><th>Hotspot</th><th>Tier</th><th>Fusion</th><th>Mixcr</th><th>Expression</th><th>CNV</th><th>NeoAntigen</th><th>Mutation Burden</th><th>TCellExTRECT</th></tr></thead>
    	<tbody>$log_cotent</tbody>
    </table>
    <HR>
    <h2><font color=red>Failed/Deleted Cases:</font></h2>
	<table id="errlog" border=1 cellspacing="2" width="60%">
    	<thead><tr><th>Patient ID</th><th>Case ID</th><th>Diagnosis</th></tr></thead>
    	<tbody>$failed_cotent</tbody>
    </table>
    <h2><font color=red>Errors:</font></h2>
	<table id="errlog" border=1 cellspacing="2" width="60%">
    	<thead><tr><th>Patient ID</th><th>Case ID</th><th>Type</th><th>Error</th></tr></thead>
    	<tbody>$err_cotent</tbody>
    </table>
};
if ($recipient ne "") {
	my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $recipient,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $data,
	);

	print_log("sending notificaiton to $recipient");

	if ($log_cotent ne "" || $failed_cotent ne "" || $err_cotent ne "") {
		$mime->send();
	}
}	 

$dbh->disconnect();

sub insertQCI {
	my ($case_id, $patient_id, $file) = @_;
	print_log("processing QCI annotation");	
	my $file_base = basename($file);
	#TSO
	my $type = "";
	my $sample_id = "";
	if ($file_base =~ /QCI-final\.txt/) {
		$type="variants";
		($sample_id)=$file_base =~ /(.*)_QCI-final\.txt/;
	}
	if ($file_base =~ /qci\.txt/) {
		($sample_id,$type)=$file_base =~ /(.*)\.(germline|somatic|rnaseq|variants|hotspot|splice|fusion|fusions)\.qci\.txt/;	
	}

	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	
	open (INFILE, '<:encoding(UTF-8)',"$file") or return;
	#open (SUMMARY_FILE, ">$report_summary_file") or return;
	my $summary = "";
	while(<INFILE>) {		
		chomp;
		my @fields = split(/\t/);		
		if ($#fields == 6) {
			print("$_\n");
			next if ($fields[0] eq "Chromosome");
			my ($chr, $pos, $ass, $ref, $alt, $act, $nooact) = @fields;
			$sth_var_qci_annotation->execute($patient_id, $case_id, $sample_id, $type, $chr, $pos, $ref, $alt, $ass, $act, $nooact);
		} else {
			if (/^(?!TMB)/ && /^(?!Report Summary)/) {
				#print SUMMARY_FILE $_."\n";
				$summary = $summary.$_."\n";
			}

		}	
	}
	close(INFILE);
	#close(SUMMARY_FILE);
	#print "$summary\n";	
	$sth_var_qci_summary->execute($patient_id, $case_id, $sample_id, $type, $summary);
	$dbh->commit();
	return 1;
}

sub insertMixcr {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $summary_file = $dir.$patient_id."/$case_id/$folder_name/mixcr/$folder_name.summarystats.RNA.txt";
	my $mixcr_file = $dir.$patient_id."/$case_id/$folder_name/mixcr/convert.$folder_name.clones.RNA.txt";
	#print $filename."\n";
	if (!-e $summary_file) {
		$summary_file = $dir.$patient_id."/$case_id/$folder_name/mixcr/$folder_name.summarystats.ALL.txt";
		$mixcr_file = $dir.$patient_id."/$case_id/$folder_name/mixcr/convert.$folder_name.clonotypes.ALL.txt";
		if (!-e $summary_file) {
			return 0;
		}
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (SUMMARY_FILE, "$summary_file") or return;
	print_log("processing Mixcr");
	$dbh->do("delete from mixcr_summary where case_id = '$case_id' and patient_id = '$patient_id' and sample_id = '$sample_id'");
	$dbh->do("delete from mixcr where case_id = '$case_id' and patient_id = '$patient_id' and sample_id = '$sample_id'");
	$dbh->commit();

	my $exp_type = "RNAseq";
	my $line = <SUMMARY_FILE>;
	while(<SUMMARY_FILE>) {
		my $print_line = "$patient_id\t$case_id\t$sample_id\t$exp_type\t$_";
		my @data_to_insert = split(/\t/, $print_line);
		#print($data_to_insert[4]."\n");
		my $chain = ".";
		if ($data_to_insert[4] =~ /.*clones\.(.*)/) {
			$chain = $1;
		} elsif ($data_to_insert[4] =~ /.*clonotypes\.(.*)/) {
			$chain = $1;
		}
		#print($chain."\n");
		$data_to_insert[4] = $chain;
		$sth_mixcr_summary->execute(@data_to_insert);
	}
	close(SUMMARY_FILE);
	open (FILE, "$mixcr_file") or return;
	$line = <FILE>;
	while(<FILE>) {
		my $print_line = "$patient_id\t$case_id\t$sample_id\t$exp_type\t.\t$_";
		my @data_to_insert = split(/\t/, $print_line);
		my $chain = ".";
		if (length($data_to_insert[9]) > 3) {
			$chain = substr($data_to_insert[9], 0, 3);
		}
		$data_to_insert[4] = $chain;
		$sth_mixcr->execute(@data_to_insert);
	}
	close(FILE);
	#push(@errors, "$patient_id\t$case_id\tNeoAntigen\tSQLLoader");
	return 1;
}

sub insertNeoAntigen {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $filename = $dir.$patient_id."/$case_id/$folder_name/NeoAntigen/$folder_name.final.txt";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing NeoAntigen");
	$dbh->do("delete from neo_antigen where case_id = '$case_id' and patient_id = '$patient_id' and sample_id = '$sample_id'");
	$dbh->commit();

	my $antigen_file = $dir.$patient_id."/$case_id/$folder_name/NeoAntigen/$folder_name.antigen.tsv";
	open(ANTIGEN_FILE, ">$antigen_file") or die "Cannot open file $antigen_file";
	my $line = <INFILE>;
	while(<INFILE>) {
		my $print_line = "$patient_id\t$case_id\t$sample_id\t$_";
		print ANTIGEN_FILE $print_line;
		my @data_to_insert = split(/\t/, $print_line);
		$sth_neo_antigen->execute(@data_to_insert);
	}
	close(INFILE);
	close(ANTIGEN_FILE);
	#push(@errors, "$patient_id\t$case_id\tNeoAntigen\tSQLLoader");
	return 1;
}

sub insertHLA {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $filename = $dir.$patient_id."/$case_id/$folder_name/HLA/$folder_name.Calls.txt";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing HLA");
	$dbh->do("delete from hla where case_id = '$case_id' and patient_id = '$patient_id' and sample_id = '$sample_id'");
	$dbh->commit();

	open(INFILE, "$filename") or die "Cannot open file $filename";
	my $line = <INFILE>;
	chomp $line;
	my @headers = split(/\t/, $line);
	while(<INFILE>) {
		chomp;
		my @data_to_insert = split(/\t/);
		next if ($#data_to_insert != $#headers);
		for (my $i=1; $i<=$#data_to_insert;$i++) {
			$sth_hla->execute($patient_id, $case_id, $sample_id, $data_to_insert[0], $headers[$i], $data_to_insert[$i]);
		}
	}
	close(INFILE);
	#push(@errors, "$patient_id\t$case_id\tNeoAntigen\tSQLLoader");
	return 1;
}

sub insertAntigen {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $filename = $dir.$patient_id."/$case_id/$folder_name/NeoAntigen/$folder_name.final.txt";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing NeoAntigen");
	$dbh->do("delete from neo_antigen where case_id = '$case_id' and patient_id = '$patient_id' and sample_id = '$sample_id'");
	$dbh->commit();

	my $antigen_file = $dir.$patient_id."/$case_id/$folder_name/NeoAntigen/$folder_name.antigen.tsv";
	open(ANTIGEN_FILE, ">$antigen_file") or die "Cannot open file $antigen_file";
	my $line = <INFILE>;
	while(<INFILE>) {
		print ANTIGEN_FILE "$patient_id\t$case_id\t$sample_id\t$_";		
	}
	close(INFILE);
	close(ANTIGEN_FILE);
	my $ret = &callSqlldr($antigen_file, $script_dir."/ctrl_files/neo_antigen.ctrl");
	if ($ret ne "ok") {
		push(@errors, "$patient_id\t$case_id\tAntigen\tSQLLoader");
		return 0;
	}	
	return 1;
}

sub insertBurden {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $file_pattern = $dir.$patient_id."/$case_id/$folder_name/qc/*.combined.mutationburden.txt";
	my @burden_files = glob $file_pattern;
	if ($#burden_files < 0) {
		$file_pattern = $dir.$patient_id."/$case_id/$folder_name/qc/*.mutationburden.txt";
	  @burden_files = glob $file_pattern;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	if ($#burden_files >= 0) {
		print_log("processing Mutationburden: $file_pattern");
		$dbh->do("delete from mutation_burden where sample_id = '$sample_id' and patient_id = '$patient_id' and case_id='$case_id'");
	} else {
		return 0;
	}
	foreach my $burden_path (@burden_files) {
		my $burden_file = basename($burden_path);
		$burden_file = substr $burden_file, length($folder_name) + 1; 
		#print "$burden_file\n";
		my $totalbase = -1;
		my $burden = -1;
		if ($burden_file =~ /(.*)\.mutationburden.txt/) {
			my $type = $1;
			open (INFILE, $burden_path);
			while (<INFILE>) {
				chomp;
				my @tokens = split(/\t/);
				if ($#tokens >= 0) {
					my $key = $tokens[0];
					last if ($key =~ /All somatic calls/);
					if ($#tokens > 0) {
						$burden = $tokens[1] if ($key eq "Mutation burden");
						$totalbase = $tokens[1] if ($key eq "Total bases");
					}
				}

			}			
			$sth_mutation_burden->execute($patient_id, $case_id, $sample_id, $1, $burden, $totalbase);
			close(INFILE);
		}
	}
	$dbh->commit();
	return 1;	
}

sub insertCNV {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $cnv_dir = $dir.$patient_id."/$case_id/$folder_name/sequenza";
	my $filename = "$cnv_dir/$folder_name/$folder_name"."_segments.txt";
	my $gene_segment_filename = "$cnv_dir/$folder_name".".segments.genes.bed";
	my $gene_level_filename = "$cnv_dir/$folder_name"."_genelevel.txt";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing CNV");
	#print "sample_id: $sample_id from $folder_name\n";
	$dbh->do("delete from var_cnv where case_id = '$case_id' and patient_id = '$patient_id'");
	my $line = <INFILE>;
	chomp $line;
	my @header_list = split(/\t/, $line);
	while(<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields != $#header_list);
		my $chr = $fields[0];
		$chr =~ s/\"//g;
		my $start_pos = $fields[1];
		my $end_pos = $fields[2];
		my $cnt = $fields[$#fields - 3];		
		my $a = $fields[$#fields - 2];
		my $b = $fields[$#fields - 1];		
		my $lpp = $fields[$#fields];
		$lpp =~ s/Inf/99999999/;
		next if ($cnt eq "NA");
		next if ($a eq "NA");
		next if ($b eq "NA");
		$sth_cnv->execute($patient_id, $case_id, $sample_id, $chr, $start_pos, $end_pos, $cnt, $a, $b, $lpp);		
	}
	$dbh->commit();
	#system("$script_dir/run_reconCNV_sequenza.sh $filename");
	#intersect gene file with segment
	system("export AWS=$aws;$script_dir/gen_sequenza_segments.sh $filename $script_dir/../../ref/hg19.genes.coding.bed");
	if ( -e $gene_segment_filename) {
		open (GENE_SEG_FILE, "$gene_segment_filename");
		print_log("processing sequenza gene segments: $gene_segment_filename");
		$dbh->do("delete from var_cnv_segment where case_id = '$case_id' and patient_id = '$patient_id'");
		while(<GENE_SEG_FILE>) {
			chomp;
			my @fields = split(/\t/);
			next if ($#fields == 0);
			my $cnt = $fields[3];
			my $lpp = $fields[6];
			$lpp =~ s/Inf/99999999/;
			next if ($cnt eq "NA");
			next if ($fields[4] eq "NA");
			next if ($fields[5] eq "NA");
			$sth_cnv_segment->execute($patient_id, $case_id, $sample_id, $fields[0], $fields[1], $fields[2], $fields[3], $fields[4], $fields[5], $lpp, $fields[7]);
		}
		close(GENE_SEG_FILE);
		$dbh->commit();
	}
	#get gene level file. Generate gene level file only if the pipeline does not generate one
	system("export AWS=$aws;$script_dir/gen_sequenza_gene_level.sh $filename $script_dir/../../ref/hg19.genes.coding.bed");
	if ( -e $gene_level_filename) {
		open (GENE_LEVEL_FILE, "$gene_level_filename");
		print_log("processing sequenza gene level: $gene_level_filename");
		$dbh->do("delete from var_cnv_gene_level where case_id = '$case_id' and patient_id = '$patient_id'");
		<GENE_LEVEL_FILE>;
		while(<GENE_LEVEL_FILE>) {
			chomp;
			my @fields = split(/\t/);
			next if ($#fields == 0);
			next if ($fields[4] == 0);	
			next if ($fields[5] == 0);	
			next if ($fields[6] == 0);			
			$sth_cnv_gene->execute($patient_id, $case_id, $sample_id, $fields[0], $fields[1], $fields[2], $fields[3], $fields[4], $fields[5], $fields[6]);
		}
		close(GENE_LEVEL_FILE);
		$dbh->commit();
	}

	system("chgrp -f $web_user $cnv_dir/*;chmod -f 770 $cnv_dir/*");
	return 1;	
}

sub insertCNVKit {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $cnv_dir = $dir.$patient_id."/$case_id/$folder_name/cnvkit";
	my $filename = "$cnv_dir/$folder_name".".call.cns";
	my $ratio_filename = "$cnv_dir/$folder_name".".cnr";
	my $gene_segment_filename = "$cnv_dir/$folder_name".".segments.genes.bed";
	my $segment_file_type = 1;
	#print $filename."\n";
	if (!-e $filename) {
		$filename = "$cnv_dir/$folder_name".".cns"; 
		$segment_file_type = 2;
		return 0 if (!-e $filename);
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing CNVKit");
	$dbh->do("delete from var_cnvkit where case_id = '$case_id' and patient_id = '$patient_id' and sample_id='$sample_id'");
	$dbh->do("delete from var_cnvkit_segment where case_id = '$case_id' and patient_id = '$patient_id' and sample_id='$sample_id'");
	my $line = <INFILE>;
	chomp $line;
	my @header_list = split(/\t/, $line);
	while(<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields != $#header_list);
		my $chr = $fields[0];
		$chr =~ s/\"//g;
		my $start_pos = $fields[1];
		my $end_pos = $fields[2];
		my $log2 = $fields[4];		
		my $depth = $fields[5];
		my $probes = $fields[6];
		my $weight = $fields[7];
		$sth_cnvkit->execute($patient_id, $case_id, $sample_id, $chr, $start_pos, $end_pos, $log2, $depth, $probes, $weight);		
	}
	$dbh->commit();
	my $gene_level = "$cnv_dir/$folder_name"."_genelevel.txt";
	system("export CONDA_PATH=$conda_path;export RECONCNV_PATH=$reconCNV_path;$script_dir/run_reconCNV.sh $ratio_filename $filename");
	system("export AWS=$aws;$script_dir/gen_cnvkit_segments.sh $filename $script_dir/../../ref/hg19.genes.coding.bed $segment_file_type");
	if ( -e $gene_segment_filename) {
		open (GENE_SEG_FILE, "$gene_segment_filename");
		print_log("processing CNVKit gene segments: $gene_segment_filename");
		while(<GENE_SEG_FILE>) {
			chomp;
			my @fields = split(/\t/);
			next if ($#fields == 0);
			if ($#fields == 13) {
				$sth_cnvkit_segment->execute($patient_id, $case_id, $sample_id, $fields[0], $fields[1], $fields[2], $fields[3], $fields[4], $fields[5], $fields[6], $fields[7], $fields[8], $fields[9], $fields[10], $fields[11], $fields[12], $fields[13]);
			} else {
				$sth_cnvkit_segment->execute($patient_id, $case_id, $sample_id, $fields[0], $fields[1], $fields[2], $fields[3], NULL, NULL, NULL, NULL, NULL, NULL, $fields[4], $fields[5], $fields[6], $fields[7]);
			}
		}
		close(GENE_SEG_FILE);
		$dbh->commit();
	}
	system("chgrp -f $web_user $cnv_dir/*;chmod -f 770 $cnv_dir/*");
	return 1;
}

sub insertCNVKitGene {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $cnv_dir = $dir.$patient_id."/$case_id/$folder_name/cnvkit";
	my $filename = "$cnv_dir/$folder_name"."_genelevel.txt";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing CNVKit gene level");
	$dbh->do("delete from var_cnvkit_gene_level where case_id = '$case_id' and patient_id = '$patient_id' and sample_id='$sample_id'");
	my $line = <INFILE>;
	chomp $line;
	my @header_list = split(/\t/, $line);
	while(<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields != $#header_list);
		if ($#header_list == 6) {
			my $chr = $fields[0];
			my $start_pos = $fields[1];
			my $end_pos = $fields[2];
			my $gene = $fields[3];
			my $cn = $fields[4];
			my $cn1 = $fields[5];
			my $cn2 = $fields[6];
			$sth_cnvkit_gene->execute($patient_id, $case_id, $sample_id, $chr, $start_pos, $end_pos, 0, 0, 0, 0,$gene, $cn, $cn1, $cn2);
		}
		if ($#header_list == 7) {		
			my $gene = $fields[0];
			my $chr = $fields[1];
			$chr =~ s/\"//g;
			my $start_pos = $fields[2];
			my $end_pos = $fields[3];
			my $log2 = $fields[4];		
			my $depth = $fields[5];
			my $weight = $fields[6];
			my $probes = $fields[7];
			$sth_cnvkit_gene->execute($patient_id, $case_id, $sample_id, $chr, $start_pos, $end_pos, $log2, $depth, $probes, $weight,$gene,0,0,0);		
		}
	}
	$dbh->commit();
	#system("$script_dir/run_reconCNV.sh $ratio_filename");
	#system("chmod 775 $cnv_dir/*");
	return 1;
}

sub insertTCellExTRECT {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $filename = $dir.$patient_id."/$case_id/$folder_name/TCellExTRECT/$folder_name"."_TCellExTRECT_naive.txt";
	my $tumor_filename = $dir.$patient_id."/$case_id/$folder_name/TCellExTRECT/$folder_name"."_TCellExTRECT_with_tumor.txt";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	if (-e $tumor_filename) {
		$filename = $tumor_filename;
	}
	open (INFILE, "$filename") or return;
	print_log("processing TCellExTRECT");
	$dbh->do("delete from tcell_extrect where case_id = '$case_id' and patient_id = '$patient_id'");
	<INFILE>;
	my $line = <INFILE>;	
	#print "$line\n";
	if ($line) {
		chomp $line;		
		my @fields = split(/\t/, $line);		
		my $status = "NA";
		my $fraction = "NA";
		my $purity = "NA";
		my $tumor_cn = "NA";
		#if no tumor
		if ($#fields == 5) {
			$fraction = $fields[1];
			$status = $fields[5];
		} else {
			$purity = $fields[1];
			$tumor_cn = $fields[2];
			$fraction = $fields[6];
			$status = $fields[10];
		}
		#print("$patient_id, $case_id, $sample_id, $status, $fraction, $purity, $tumor_cn\n");
		$sth_tcell_extrect->execute($patient_id, $case_id, $sample_id, $status, $fraction, $purity, $tumor_cn);
		$dbh->commit();
		return 1;
	}
	
}

sub insertCNVTSO500 {
	my ($dir, $folder_name, $patient_id, $case_id) = @_;	
	my $filename = $dir.$patient_id."/$case_id/$folder_name/cnvTSO/$folder_name".".cns";
	#print $filename."\n";
	if (!-e $filename) {
		return 0;
	}
	my $sample_id = $folder_name;
	$sample_id =~ s/Sample_//;
	if (exists $sample_alias{$sample_id}) {
		$sample_id = $sample_alias{$sample_id};
	}
	open (INFILE, "$filename") or return;
	print_log("processing CNVTSO500");
	$dbh->do("delete from var_cnvtso where case_id = '$case_id' and patient_id = '$patient_id'");
	my $line = <INFILE>;
	chomp $line;
	my @header_list = split(/\t/, $line);
	while(<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields != $#header_list);
		my $gene = $fields[0];
		my $chr = $fields[1];
		$chr =~ s/\"//g;
		my $start_pos = $fields[2];
		my $end_pos = $fields[3];		
		my $dup_del = $fields[4];
		$dup_del=~s/<//;
		$dup_del=~s/>//;
		my $fc = $fields[5];		
		$sth_cnvtso->execute($patient_id, $case_id, $sample_id, $chr, $start_pos, $end_pos, $gene, $dup_del, $fc);		
	}
	$dbh->commit();
	return 1;
}

sub insertSplice {
	my ($case_id, $patient_id, $filename, $path) = @_;
	
	if (!-e $filename) {
		return 0;
	}
	my $type = 'splice';
	if (exists $cases{$case_id.$patient_id.$type}) {
		my $status = $cases{$case_id.$patient_id.$type};
		
		return if ($status eq "closed");
	} else {
		my $sql = "insert into var_type values('$case_id', '$patient_id', '$type', 'active', '', 1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)";
		#print "$sql\n";
		$dbh->do($sql);		
		$dbh->commit();
	}	
	open (INFILE, "$filename") or return;
	print_log("processing Splicing");
	$dbh->do("delete from var_splicing where case_id = '$case_id' and patient_id = '$patient_id'");
	my $line = <INFILE>;
	chomp $line;
	my @header_list = split(/\t/, $line);
	while(<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields != $#header_list);
		my $chr = $fields[0];
		$chr =~ s/\"//g;
		my $start_pos = $fields[1];
		my $end_pos = $fields[2];
		my $ref = $fields[3];
		my $alt = $fields[4];
		my $filter = $fields[5];		
		my $gene = $fields[6];
		my $support_reads = $fields[7];
		my $exons = $fields[8];		
		my $trans_ids = $fields[9];
		$sth_splice->execute($patient_id, $case_id, $chr, $start_pos, $end_pos, $ref, $alt, $filter, $gene, $support_reads, $exons, $trans_ids);		
	}
	$dbh->commit();
	return 1;
}

sub insertNewFusion {
	my ($case_id, $patient_id, $file, $path) = @_;
	return if (!-e $file);
	my $type = 'fusion';
	if (exists $cases{$case_id.$patient_id.$type}) {
		my $status = $cases{$case_id.$patient_id.$type};
		#print "status: $status\n";
		return if ($status eq "closed");
	} else {
		my $sql = "insert into var_type values('$case_id', '$patient_id', '$type', 'active', '', 1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)";
		#print "$sql\n";
		$dbh->do($sql);		
		$dbh->commit();
	}
	#print "processing fusion file: $file\n";
	open(INFILE, "$file") or die "Cannot open file $file";
	<INFILE>;
	my $del_sql = "delete from var_fusion where case_id = '$case_id' and patient_id = '$patient_id'";
	$dbh->do($del_sql);
	
	my $min_column = 21;
	while (<INFILE>) {
		chomp;
		my @fields = split(/\t/);				
		next if ($#fields < ($min_column - 1));
		my @key = @fields[0..5];
		my $sample_id = $fields[6];
		$sample_id =~ s/Sample_//;		
		if (exists $sample_alias{$sample_id}) {
			$sample_id = $sample_alias{$sample_id};
		}		
		my @master = (($case_id, $patient_id), @key, ($sample_id, $fields[7]), @fields[8..20]);
		#my @details = (@key, @fields[18..20]);
		#print("@master\n");
		#print("@details\n");
		$sth_fu->execute(@master);
		# Now we removed the detailed table
		#try {
		#	$sth_fu_details->execute(@details);
		#} catch {
		#	if ($sth_fu_details->errstr !~ /ORA-00001/) {
		#		die $_;
				#	print "Unique constraint error\n";
		#	}
		#};
		$dbh->commit();
	}
}


sub insertQC {
	my ($case_id, $patient_id, $file, $type) = @_;
	#$dbh->do("delete from var_qc where case_id = '$case_id' and patient_id = '$patient_id' and type = '$type'");
	print_log("processing QC file: $file");
		
	open(INFILE, "$file") or die "Cannot open file $file";
	
	my $line = <INFILE>;
	chomp $line;
	if ($line eq "") {
		$line = <INFILE>;
	}
	my @header_list = split(/\t/, $line);
	my %headers = ();
	my @rnaV2headers=("Sample","Total Purity Filtered Reads Sequenced", "Mapped","Mapped Unique", "Unique Rate of Mapped","Duplication Rate of Mapped","rRNA rate","Exonic Rate","Intronic Rate", "Fragment Length Mean");
		for (my $i=0;$i<=$#header_list;$i++) {
			$header_list[$i] =~ s/^#//;
			$headers{$header_list[$i]} = $i;
		}
	
	while (<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields < $#header_list);
		my $sample_id = $fields[1];
		$sample_id =~ s/Sample_//;
		
		if (exists $sample_alias{$sample_id}) {
			$sample_id = $sample_alias{$sample_id};			
		}

		#next if ($fields[0] =~ /patient/i);
		for (my $i=2;$i<=$#fields;$i++) {
			if($type ne "rnaV2"){
				my $attr_name = $header_list[$i];
				$sth_qc->execute($case_id, $patient_id, $sample_id, $attr_name, $fields[$i], $type);
			}
			elsif($type eq "rnaV2"){
				foreach (@rnaV2headers) {
  					if ($header_list[$i] eq $_) {
  						#print $_."\n";
    					my $attr_name = $header_list[$i];
						$sth_qc->execute($case_id, $patient_id, $sample_id, $attr_name, $fields[$i], $type);
 					}
				}
			}
		}		

	}
	$dbh->commit();
}

sub getSampleCov {
	#my ($chr, $start, $end, $ref, $alt, $sample_id, $var_smp_ref) = @_;
	my ($chr, $start, $end, $ref, $alt, $sample_id) = @_;
	#my %var_smp = %{$var_smp_ref};
	my $smp_key = join("\t",$chr, $start, $end, $ref, $alt, $sample_id);
	my $var_cov = 0;
	my $total_cov = 0;
	
	if (exists $var_smp{$smp_key}) {
		my $smp_values = $var_smp{$smp_key};
		my @fields = split(/\t/, $smp_values);
		$total_cov = $fields[3];
		$var_cov = $fields[4];		
	}
	return ($var_cov, $total_cov);
}

sub getMatchTumorSample {
	my ($chr, $start, $end, $ref, $alt, $sample_id) = @_;
	#my %var_smp = %{$var_smp_ref};
	my $var_cov = 0;
	my $total_cov = 0;
	my $tumor_sample_id = "";
	if (exists $match_tumor{$sample_id}) {
		my @tumor_samples = @{$match_tumor{$sample_id}};
		foreach my $tumor_sample (@tumor_samples) {
			my $smp_key = join("\t",$chr, $start, $end, $ref, $alt, $tumor_sample);
			if (exists $var_smp{$smp_key}) {
				my $smp_values = $var_smp{$smp_key};
				my @fields = split(/\t/, $smp_values);
				my $tumor_total_cov = $fields[3];
				my $tumor_var_cov = $fields[4];
				if ($tumor_total_cov > $total_cov) {
					$tumor_sample_id = $tumor_sample;
					$total_cov = $tumor_total_cov;
					$var_cov = $tumor_var_cov;
				}
			}
		}
	}
	return ($tumor_sample_id, $var_cov, $total_cov);
}

sub insertTier {	
	my ($type, $case_id, $patient_id, $sample_id, $tier_file, $tier_avia_file) = @_;	
	if ($use_sqlldr) {		
		#print "=========>output file ($type): $tier_file\n";
		open(TIER_FILE, ">>$tier_file") or die "Cannot open file $tier_file";
		open(TIER_FILE_AVIA, ">>$tier_avia_file") or die "Cannot open file $tier_avia_file";
	}
	my $curl = "$url/getVarTier/$patient_id/$case_id/$type/$sample_id/avia";
	print "$curl\n";#hv
	my @lines = readpipe("php $script_dir/httpClient.php url=$curl");
	
	#my( $status, $results ) = getWithStatus( $curl );
	#print "$status\n";#hv
	#print "$results\n";#hv
	#if( $status ne "200 OK" ) {
    # 	push(@errors, "$patient_id\t$case_id\tTier\tURL error: $curl, status: $status");
    # 	return;	
	#}
	
	#if (!$results) {
	#	$results = "";
	#}
	#my @lines = split(/\n/, $results);

	#my @lines = readpipe($cmd);
	my $total_lines = $#lines + 1;
	print_log("inserting $total_lines tier(_avia) data...");
	foreach my $line (@lines) {
		chomp $line;
		next if ($line eq "");
		#print("inserting $line\n");
		my @fields = split(/\t/, $line);
		my $gene_idx = 6;
		my $gene = $fields[$gene_idx];
		my $somatic_tier = $fields[$gene_idx+1];
		my $germline_tier = $fields[$gene_idx+2];
		my $maf = $fields[$gene_idx+3];
		my $total_cov = $fields[$gene_idx+4];
		my $vaf = $fields[$gene_idx+5];
		my $annotation = $fields[$gene_idx+6];		
		if ($use_sqlldr) {
			if ($annotation eq "AVIA") {
				print TIER_FILE_AVIA join("|", $fields[0],$fields[1],$fields[2],$fields[3],$fields[4],$case_id, $patient_id, $sample_id, $type, $somatic_tier, $germline_tier,$gene,$maf,$total_cov,$vaf)."\n";
			} else {
				print TIER_FILE join("|", $fields[0],$fields[1],$fields[2],$fields[3],$fields[4],$case_id, $patient_id, $sample_id, $type, $somatic_tier, $germline_tier,$gene, $maf,$total_cov,$vaf)."\n";
			}
		} else {
			if ($annotation eq "AVIA") {
				#print("inserting avia\n");
				$sth_tier_avia->execute($fields[0],$fields[1],$fields[2],$fields[3],$fields[4],$case_id, $patient_id, $sample_id, $type, $somatic_tier, $germline_tier, $gene,$maf,$total_cov,$vaf);
			} 
		}
	}
	$dbh->commit();
}

sub insertSample {	
	my ($type, $case_id, $patient_id, $file, $path, $sample_file) = @_;
	
	#$sample_file = "";

	if (exists $cases{$case_id.$patient_id.$type}) {
		my $status = $cases{$case_id.$patient_id.$type};
		#return if ($status eq "closed");
	} else {
		my $sql = "insert into var_type values('$case_id', '$patient_id', '$type', 'active', '', 1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)";
		#print "$sql\n";
		$dbh->do($sql);		
		$dbh->commit();
	}
	return if (!-e $file);
	#$dbh->do("delete from $var_sample_tbl where case_id='$case_id' and patient_id='$patient_id' and type='$type'");
	#$dbh->do("delete from $var_patient_tbl where case_id='$case_id' and patient_id='$patient_id' and type='$type'");
	print_log("processing $type (reading $file)");

	#if (-e $sample_file && !$replaced_old && $use_sqlldr) {
	#	$dbh->commit();
	#	return;
	#}
	#print "Uploading $patient_id.$type\n";

	open(INFILE, "$file") or die "Cannot open file $file";
	%var_smp = ();
	
	if ($use_sqlldr) {
		$dbh->commit();		
		#print "=========>output file: $sample_file\n";
		open(SAMPLE_FILE, ">>$sample_file") or die "Cannot open file $sample_file";		
	}
	#first pass, read db files
	while (<INFILE>) {
		chomp;
		my @fields = split(/\t/);
		next if ($#fields < 10);
		for (my $i=0;$i<=$#fields;$i++) {
			if ($fields[$i] eq "-1" || $fields[$i] eq "." || $fields[$i] eq "-" || $fields[$i] eq "NA") {
				$fields[$i] = "";
			}
		}
		if (!exists $chr_list{$fields[0]}) {
			next;
		}
		my $caller_fn = 6;
		if ($#fields == 12) {
			$caller_fn = 8;
		}
		$fields[3] = "-" if ($fields[3] eq "");
		$fields[4] = "-" if ($fields[4] eq "");
		my $total_cov = $fields[$caller_fn + 3];
		my $var_cov = $fields[$caller_fn + 4];
		next if ($var_cov =~ /,/);
		if ($total_cov eq "" || $total_cov eq "0") {
			$total_cov = 0;
			$var_cov = 0;
		}

		my $sample_id = $fields[5];
		$sample_id =~ s/Sample_//;
		my $tissue_cat = "normal";
		
		my $exp_type = "";
		my $relation = "";

		#print $_ if ($fields[1] eq "48305819");

		if (exists $sample_type{$sample_id}) {
			$tissue_cat = $sample_type{$sample_id};	
			$exp_type = $sample_exp_type{$sample_id};
			$relation = $sample_relation{$sample_id};
		}
		elsif (exists $sample_alias{$sample_id}) {
				$sample_id = $sample_alias{$sample_id};
				$tissue_cat = $sample_type{$sample_id};	
				$exp_type = $sample_exp_type{$sample_id};
				$relation = $sample_relation{$sample_id};			
		}		

		if ($tissue_cat eq "cell line") {
			$tissue_cat = "tumor";
		}

		if ($tissue_cat eq "xeno") {
			$tissue_cat = "tumor";
		}

		if ($tissue_cat eq "blood") {
			$tissue_cat = "normal";
		}
		if ($type eq 'germline') {
			next if ($total_cov eq "0");
			next if ($var_cov eq "0");			
		}		

		if (length($fields[3]) > 255 || length($fields[4]) > 255) {
			next;
		}
		my $key = join("\t",$fields[0], $fields[1], $fields[2], $fields[3], $fields[4]);
		my $smp_key = join("\t",$fields[0], $fields[1], $fields[2], $fields[3], $fields[4], $sample_id);
		my $caller = $fields[$caller_fn];

		if ($caller eq "bam2mpg") {
			next;
		}
		if ($exp_type eq "RNAseq" && $type eq "somatic") {
			$caller = "mpileup";			
		}
		#print "$smp_key\n" if ($exp_type eq "RNAseq");
		#print "$smp_key\n" if ($fields[1] eq "48305819");
		if ($type eq "somatic" && $fields[1] eq "50747071") {
				print "key==>$smp_key\n";
		}
		$var_smp{$smp_key} = join("\t", $caller, $fields[$caller_fn + 1], $fields[$caller_fn + 2], $total_cov, $var_cov, $tissue_cat, $exp_type, $relation);
	}

	my %vaf_ratios = ();
	my %vafs = ();
	my %var_covs = ();
	my %total_covs = ();
	my %exp_var_covs = ();
	my %exp_total_covs = ();
	my %pat_vars = ();
	my $varCount=0;
	#second pass find match normal & rnaseq
	#while (my ($smp_key, $smp_value) = each %var_smp) {
	foreach my $smp_key (keys %var_smp) {
		my $smp_value = $var_smp{$smp_key};
		my ($chr, $start, $end, $ref, $alt, $sample_id) = split(/\t/, $smp_key);
		my ($caller, $qual, $fisher, $total_cov, $var_cov, $tissue_cat, $exp_type, $relation) = split(/\t/, $smp_value);
		my $key = join("\t",$chr, $start, $end, $ref, $alt);
		my $vaf = ($total_cov == 0)? 0: ($var_cov/$total_cov);
		my $vaf_ratio = 1;
		my $tumor_var = 0;
		my $tumor_total = 0;
		my $normal_var = 0;
		my $normal_total = 0;
		my $rnaseq_var = 0;
		my $rnaseq_total = 0;	
		my $sample_name = "";
		my $normal_sample_id = "";
		my $rnaseq_sample_id = "";
		my $tumor_sample_id = "";
		#get tumor, normal and rnaseq read count
		if($sample_id eq "CL0138_T1D_PS_HKWYFBGX3"){
					print $sample_id." SAMPLE ID"."\n";
					print $match_normal{"CL0138_T1D_E_HKWYFBGX3"}."MATCHED NORMAL"."\n";
				}
		if ($tissue_cat eq "normal") {
			$normal_var = $var_cov;
			$normal_total = $total_cov;			
			($tumor_sample_id, $tumor_var, $tumor_total) = getMatchTumorSample($chr, $start, $end, $ref, $alt, $sample_id);
			
		} else {
			$tumor_var = $var_cov;
			$tumor_total = $total_cov;
			if (exists $match_normal{$sample_id}) {

				my $normal_sample_id = $match_normal{$sample_id};
				if($sample_id eq "CL0138_T1D_PS_HKWYFBGX3"){
					print $normal_sample_id." NORMAL TOTAL ".$normal_total."\n";
				}

				my $normal_sample_key = join("\t",$chr, $start, $end, $ref, $alt, $normal_sample_id);				
				if ($type eq "somatic" && $start eq "50747071") {
						print "$normal_sample_key\n";
				}
				if (exists $var_smp{$normal_sample_key}) {
					my $smp_values = $var_smp{$normal_sample_key};					
					my @fields = split(/\t/, $smp_values);
					$normal_total = $fields[3];
					
					$normal_var = $fields[4];
					#($normal_var, $normal_total) = getSampleCov($chr, $start, $end, $ref, $alt, $normal_sample_id);
				} else {
					next if ($type eq "germline");
				}
			}
		}
		if ($exp_type ne "RNAseq") {			
			if (exists $match_rnaseq{$sample_id}) {
				my $rnaseq_sample_id = $match_rnaseq{$sample_id};
				($rnaseq_var, $rnaseq_total) = getSampleCov($chr, $start, $end, $ref, $alt, $rnaseq_sample_id);				
			}
		}
		my $normal_vaf = ($normal_total == 0)? 0: ($normal_var/$normal_total);
		my $tumor_vaf = ($tumor_total == 0)? 0: ($tumor_var/$tumor_total);
		if ($tumor_total != 0 && $normal_total != 0) {
			$vaf_ratio = ($normal_vaf == 0)? 0 : $tumor_vaf / $normal_vaf ;
		}
		# if multiple VAF ratio, find max one (multiple tumors)
		if (exists($vaf_ratios{$key})) {
			my $old_vaf_ratio = $vaf_ratios{$key};
			if ($old_vaf_ratio < $vaf_ratio) {
				$vaf_ratios{$key} = $vaf_ratio;
			}
		} else {
			$vaf_ratios{$key} = $vaf_ratio;
		}	

		if (exists $sample_names{$sample_id}) {
			$sample_name = $sample_names{$sample_id};
		}
		#if germline, then we focus on normal sample
		if ($type eq "germline") {
			if ($tissue_cat eq "normal") {
				$pat_vars{$key} = '';
				# if multiple normal samples, find largest total cov
				if (exists($total_covs{$key})) {
					my $old_total_cov = $total_covs{$key};
					if ($old_total_cov < $total_cov) {
						$var_covs{$key} = $var_cov;
						$total_covs{$key} = $total_cov;
					}
				} else {
					$var_covs{$key} = $var_cov;
					$total_covs{$key} = $total_cov;
				}	
				# if multiple normal samples, find largest VAF
				if (exists($vafs{$key})) {
					my $old_vaf = $vafs{$key};
					if ($old_vaf < $vaf) {
						$vafs{$key} = $vaf;
					}
				} else {
					$vafs{$key} = $vaf;
				}				
			} # end of if ($tissue_cat eq "normal")
			else {
				next if (!exists $match_normal{$sample_id});
				my $normal_sample_id = $match_normal{$sample_id};								
				my $normal_smp_key = join("\t",$chr, $start, $end, $ref, $alt, $normal_sample_id);
				#if tumor in germline but no normal found, skip this sample
				next if (!exists $var_smp{$normal_smp_key});
			}
		}
		else { # if somatic, variant, RNAseq, we focus on tumor sample (except for RNAseq)
			if ($tissue_cat eq "tumor" || $type eq "rnaseq") {
				$pat_vars{$key} = '';
				# if somatic, then find paried normal and RNAseq
				if ($type eq "somatic") {					
					if ($exp_type ne "RNAseq") {						
						my $normal_sample_id = $match_normal{$sample_id};
						#if (!$normal_sample_id) {
						#	print "$sample_id\n";
						#}
						my $normal_smp_value = "";
						my $rnaseq_sample_id = $match_rnaseq{$sample_id};
						if (exists $match_normal{$sample_id}) {
							my $normal_sample_id = $match_normal{$sample_id};
							my $normal_smp_key = join("\t",$chr, $start, $end, $ref, $alt, $normal_sample_id);
							if (exists $var_smp{$normal_smp_key}) {
								$normal_smp_value = $var_smp{$normal_smp_key};				
							}
						}
						 my $rnaseq_smp_value = "";
						 if (exists $match_rnaseq{$sample_id} ) {					 	
							my $rnaseq_sample_id = $match_rnaseq{$sample_id};																	
							my $rnaseq_smp_key = join("\t",$chr, $start, $end, $ref, $alt, $rnaseq_sample_id);
							if (exists $var_smp{$rnaseq_smp_key}) {
								$rnaseq_smp_value = $var_smp{$rnaseq_smp_key};				
							}
						}
						
						# if paired tumor exists, calculate VAF ratio (this step is not required for somatic variants)
						if ($normal_smp_value ne "") {
							my @normal_fields = split(/\t/, $normal_smp_value);
							my $normal_total = $normal_fields[3];
							my $normal_var = $normal_fields[4];
							my $normal_vaf = ($normal_total == 0)? 0: ($normal_var/$normal_total);
							$vaf_ratio = ($normal_vaf == 0)? 0 : $vaf / $normal_vaf ;
							# if multiple VAF ratio, find max one (multiple tumors)
							if (exists($vaf_ratios{$key})) {
								my $old_vaf_ratio = $vaf_ratios{$key};
								if ($old_vaf_ratio < $vaf_ratio) {
									$vaf_ratios{$key} = $vaf_ratio;
								}
							} else {
								$vaf_ratios{$key} = $vaf_ratio;
							}
						}
						
						# if paired RNAseq exists, calculate RNAseq coverage
						if ($rnaseq_smp_value ne "") {						
							my @rnaseq_fields = split(/\t/, $rnaseq_smp_value);
							$rnaseq_total = $rnaseq_fields[3];
							$rnaseq_var = $rnaseq_fields[4];
							# if multiple RNAseq coverage, find max variant coverage (multiple RNAseq)
							if (exists($exp_var_covs{$key})) {
								my $old_var_cov = $exp_var_covs{$key};
								if ($old_var_cov < $rnaseq_var) {
									$exp_var_covs{$key} = $rnaseq_var;
									$exp_total_covs{$key} = $rnaseq_total;
								}
							} else {
								$exp_var_covs{$key} = $rnaseq_var;
								$exp_total_covs{$key} = $rnaseq_total;							
							}
						}					
						# if multiple tumor samples, find largest total cov
						if (exists($total_covs{$key})) {
							my $old_total_cov = $total_covs{$key};
							if ($old_total_cov < $total_cov) {
								$var_covs{$key} = $var_cov;
								$total_covs{$key} = $total_cov;
							}
						} else {
							$var_covs{$key} = $var_cov;
							$total_covs{$key} = $total_cov;
						}

						# if multiple tumor samples, find largest VAF
						if (exists($vafs{$key})) {
							my $old_vaf = $vafs{$key};
							if ($old_vaf < $vaf) {
								$vafs{$key} = $vaf;
							}
						} else {
							$vafs{$key} = $vaf;
						}
					}
				} # end of somatic
				#RNAseq and Variants
				else {
					# if multiple samples, find largest total cov
					if (exists($total_covs{$key})) {
						my $old_total_cov = $total_covs{$key};
						if ($old_total_cov < $total_cov) {
							$var_covs{$key} = $var_cov;
							$total_covs{$key} = $total_cov;
						}
					} else {
						$var_covs{$key} = $var_cov;
						$total_covs{$key} = $total_cov;
					}

					# if multiple samples, find largest VAF
					if (exists($vafs{$key})) {
						my $old_vaf = $vafs{$key};
						if ($old_vaf < $vaf) {
							$vafs{$key} = $vaf;
						}
					} else {
						$vafs{$key} = $vaf;
					}
				}
			} # end of if ($tissue_cat eq "tumor")			
		}
		
		if ($use_sqlldr) {
			print SAMPLE_FILE join("\t", $chr, $start, $end, $ref, $alt, $case_id, $patient_id, $sample_id, $sample_name, $caller, $qual, $fisher, $type, $tissue_cat, $exp_type, $relation, $var_cov, $total_cov, $vaf, $normal_var, $normal_total, $normal_vaf, $rnaseq_var, $rnaseq_total, $vaf_ratio)."\n";			
		} else {
			if ($start == "29474135") {
				print join(",", $chr, $start, $end, $ref, $alt, $case_id, $patient_id, $sample_id, $sample_name, $caller, $qual, $fisher, $type, $tissue_cat, $exp_type, $relation, $var_cov, $total_cov, $normal_var, $normal_total, $rnaseq_var, $rnaseq_total, $vaf_ratio, $vaf, $normal_vaf)."\n";
			}
			$varCount++;
			$sth_smp->execute($chr, $start, $end, $ref, $alt, $case_id, $patient_id, $sample_id, $sample_name, $caller, $qual, $fisher, $type, $tissue_cat, $exp_type, $relation, $var_cov, $total_cov, $normal_var, $normal_total, $rnaseq_var, $rnaseq_total, $vaf_ratio, $vaf, $normal_vaf);
		}

	} # end of while
	if (!$use_sqlldr){
		print_log("$varCount variants inserted");
	}

	foreach my $key (keys %pat_vars) {
		my ($chr, $start, $end, $ref, $alt) = split(/\t/, $key);
		my $vaf_ratio = ($type eq "germline")? 0 : 1;
		my $var_cov = 0;
		my $total_cov = 0;
		my $vaf = 0;
		my $exp_var_cov = 0;
		my $exp_total_cov = 0;
		
		$vaf = $vafs{$key} if (exists($vafs{$key}));
		$var_cov = $var_covs{$key} if (exists($var_covs{$key}));
		$total_cov = $total_covs{$key} if (exists($total_covs{$key}));
		$vaf_ratio = $vaf_ratios{$key} if (exists($vaf_ratios{$key}));
		$exp_var_cov = $exp_var_covs{$key} if (exists($exp_var_covs{$key}));
		$exp_total_cov = $exp_total_covs{$key} if (exists($exp_total_covs{$key}));
		
		if ($use_sqlldr) {
			print PATIENT_FILE join("\t", $chr, $start, $end, $ref, $alt, $case_id, $patient_id, $type, $var_cov, $total_cov, $vaf, $vaf_ratio, $exp_var_cov, $exp_total_cov, '', '')."\n";			
		} else {
			#$sth_pat->execute($chr, $start, $end, $ref, $alt, $case_id, $patient_id, $type, $var_cov, $total_cov, $vaf, $vaf_ratio, $exp_var_cov, $exp_total_cov, '', '');
		}
	}

	if ($use_sqlldr) {
		close(SAMPLE_FILE);
		close(PATIENT_FILE);		
	}
	else {
		$dbh->commit();
	}
	
}


sub print_log {
    my ($msg) = @_;
    #open CMD_FILE, ">>$cmd_log_file" || print "cannot create command log file";
    #print CMD_FILE "[".localtime->strftime('%Y-%m-%d %H:%M:%S')."] $msg\n";
    #close(CMD_FILE);
    $msg = "[".localtime->strftime('%Y-%m-%d %H:%M:%S')."] $msg\n";
	  print "$msg";
}

sub getDiagnosis {
	my ($patient_id) = @_;
	$sth_diag->execute($patient_id);
	my $diagnosis = "";
	my @row = $sth_diag->fetchrow_array;
	if (@row) {
		$diagnosis = $row[0];
	}
	$sth_diag->finish;
	return $diagnosis;
}

sub getWithStatus {
    my $url = shift;
    my $content;
    my $ua = LWP::UserAgent->new;
 	$ua->timeout(1000);
 	$ua->env_proxy;
 	my $response = $ua->get($url);
 	return $response->status_line, $response->decoded_content;
}

sub callSqlldr {
	my ($data_file, $ctrl_file) = @_;

	my $bad_file = $data_file.".bad";
	my $log_file = $data_file.".log";
	system("rm -f $bad_file $log_file");
	my $user = "$username/$passwd@//$host:$port/$sid.ncifcrf.gov";
	my $cmd = "$script_dir/runSqlldr.sh $user $data_file $ctrl_file $bad_file $log_file";
	print "$cmd\n";
	system($cmd);
	if (-s $bad_file) {
		return "SQLLoader error";
	} else {
		return "ok";
	}

}
