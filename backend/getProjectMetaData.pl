#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Try::Tiny;
use MIME::Lite; 
use JSON;
use Data::Dumper;

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $input_file_list;
my $patient_mapping_file;
my $modified_flag_list;
my $keep_old = 0;
my $update_case = 0;
my $rm_orphan_prj = 0;
my $database_name = "development";
my $verbose = 0;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -i  <string>  Input text files (comma separated)
  -m  <string>	Modified flags   (comma separated)
  -u            Update case information and refresh views
  -n  <string>  Database name (default: $database_name)
  -p  <string>  Patient mapping file
  -r            Remove orphan projects
  
__EOUSAGE__



GetOptions (
  'i=s' => \$input_file_list,
  'm=s' => \$modified_flag_list,
  'n=s' => \$database_name,
  'p=s' => \$patient_mapping_file,
  'u'   => \$update_case,
  'r'	=> \$rm_orphan_prj,
  'v'	=> \$verbose
);

if (!$input_file_list) {
    die "input file list are missing\n$usage";
}

my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,
}) || die( $DBI::errstr . "\n" );

my $tbl_var_smp = "var_annotation_samples";

# Get the RNAseq sample data then we know what projects have been changed and we can refresh those projects
my %old_project_samples = ();
my %new_project_samples = ();
my $sth_prj_rnaseq_smp = $dbh->prepare("select project_id,sample_id from project_samples where exp_type='RNAseq' order by project_id,sample_id");
$sth_prj_rnaseq_smp->execute();
while (my @row = $sth_prj_rnaseq_smp->fetchrow_array) {
	my $project_id = $row[0];
	my $sample_id = $row[1];
	push @{$old_project_samples{$project_id}}, $sample_id;	
}
$sth_prj_rnaseq_smp->finish;
my %patient_mapping = ();
if ($patient_mapping_file) {
	open(PATIENT_MAPPING_FILE, "$patient_mapping_file") or die "Cannot open file $patient_mapping_file";
	while (<PATIENT_MAPPING_FILE>) {
		chomp;
		my ($original_id, $new_id) = split(/\t/);
		$patient_mapping{$original_id} = $new_id;
	}
}
if (!$keep_old) {
	my $num = $dbh->do("delete from sample_details where exists(select * from samples, patients where sample_details.sample_id=samples.sample_id and samples.patient_id=patients.patient_id and user_id=1)");
	print "deleted $num from sample_details\n";
	$num =$dbh->do("delete from samples where exists(select * from patients where samples.patient_id=patients.patient_id and user_id=1)");	
	print "deleted $num from samples\n";
	$num = $dbh->do("delete from project_patients where exists(select * from patients where project_patients.patient_id=patients.patient_id and user_id=1) and exists(select * from projects where project_patients.project_id=projects.id and user_id=1)");
	print "deleted $num from project_patients\n";
	$num=$dbh->do("delete from sample_cases where exists(select * from patients where sample_cases.patient_id=patients.patient_id and user_id=1)");
	print "deleted $num from sample_cases\n";
	$num=$dbh->do("delete from project_samples where exists(select * from patients where project_samples.patient_id=patients.patient_id and user_id=1) and exists(select * from projects where project_samples.project_id=projects.id and user_id=1)");
	print "deleted $num from project_samples\n";
	$num =$dbh->do("delete from patients where user_id=1");	
	print "deleted $num from patients\n";
	print "DELETED OLD on $sid\n";	
	# $dbh->commit();	##20190903
	#$dbh->do("truncate table projects");
}

my @input_files = split(/,/, $input_file_list);
my @input_flags = split(/,/, $modified_flag_list) if ($modified_flag_list);
my $sql_smp = "insert into samples values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
my $sql_pat = "insert into patients values(?,?,?,?,?,?,?,?)";
my $sql_smp_dtl = "insert into sample_details values(?,?,?)";

my $sql_prj = "insert into projects (name, description, updated_at, created_at, isstudy, status, user_id, version) values(?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP, '1', '0', '1', '19')";
my $sql_prj_pat = "insert into project_patients values(?,?,?)";
my $sql_smp_case = "insert into sample_cases values(?,?,?,?,?)";
my $sql_prj_smp = "insert into project_samples values(?,?,?,?,?,?,?,?,?,?)";

my $sth_smp = $dbh->prepare($sql_smp);
my $sth_pat = $dbh->prepare($sql_pat);
my $sth_smp_dtl = $dbh->prepare($sql_smp_dtl);

my $sth_prj = $dbh->prepare($sql_prj);
my $sth_prj_pat = $dbh->prepare($sql_prj_pat);
my $sth_smp_case = $dbh->prepare($sql_smp_case);
my $sth_prj_smp = $dbh->prepare($sql_prj_smp);

my $sth_projects = $dbh->prepare("select id, name from projects where user_id=1");
my $sth_prj_id = $dbh->prepare("select id from projects where name = ?");
my $sth_check_lib_type = $dbh->prepare("select * from samples s1 where exists(select * from samples s2 where (s2.sample_id=s1.normal_sample or s2.sample_name=s1.normal_sample) and s1.exp_type=s2.exp_type and lower(regexp_replace(s1.library_type, '[\.utr]*\.v[0-9]\$', '')) <> lower(regexp_replace(s2.library_type, '[\.utr]*\.v[0-9]\$', ''))) and exp_type in ('Exome', 'Panel') and sample_id <> 'NCI0243_T_E_HH3CWBGXX'");
my $sth_check_normal = $dbh->prepare("select sample_id, normal_sample from samples s1 where (select count(*) from samples s2 where s2.sample_id=s1.normal_sample or s2.sample_name=s1.normal_sample) > 1");
my $sth_check_rnaseq = $dbh->prepare("select sample_id, rnaseq_sample from samples s1 where (select count(*) from samples s2 where s2.sample_id=s1.rnaseq_sample or s2.sample_name=s1.rnaseq_sample) > 1");

$sth_projects->execute();
my %projects = ();
my %project_patients = ();
my %sample_cases = ();

while (my @row = $sth_projects->fetchrow_array) {
	my $project_id = $row[0];
	my $project_name = $row[1];
	$projects{$project_name} = $project_id;
}
$sth_projects->finish;

my $default_case_id = "20160415";
my %patients = ();
my %samples = ();

my @errors = ();
my %projects_in_master = ();

my @modified_files = ();
for (my $file_idx=0; $file_idx<=$#input_files; $file_idx++) {

	my $input_file = $input_files[$file_idx];	
	open(IN_FILE, "$input_file") or die "Cannot open file $input_file";
	print "opening $input_file"  and <STDIN>  if ($verbose);
	$input_file = basename($input_file);
	push @modified_files, $input_file if ($modified_flag_list && $input_flags[$file_idx]);

	my $line = <IN_FILE>;
	chomp $line;
	my @headers = split(/\t/,$line);
	my %header_idx = ();
	my $idx = 0;
	foreach my $header(@headers) {
		$header_idx{$header} = $idx++;
	}

	my $num_fields = $#headers;

	while (<IN_FILE>) {
		chomp;
		# $verbose = ($_=~/RMS2162/)?1:0;
		my $error="False";
		my @fields = split(/\t/);
		#next if ($#fields < $num_fields);
		next if ($#fields == 0);
		# clear NA fields
		for (my $i = 0; $i<=$#fields; $i++) {
			$fields[$i] = "" unless defined($fields[$i]);		
			if ($fields[$i] eq '#N/A!' || $fields[$i] eq '#N/A' || $fields[$i] eq 'Unknown' || $fields[$i] eq '0') {
				$fields[$i] = '';
			}
		}
		my $platform = "";
		my $bio_id = $fields[$header_idx{'Biomaterial ID'}];
		my $name = defined($header_idx{'Name'})? $fields[$header_idx{'Name'}]: "";
		my $src_bio_id = $fields[$header_idx{'Source Biomaterial ID'}];
		next unless ($bio_id && $bio_id ne "");
		#my $sub_id = defined($header_idx{'Subject ID'})? $fields[$header_idx{'Subject ID'}]: "";
		my $type = $fields[$header_idx{'Type'}];

		my $illumina_id = "";
		my $cgi_sample_id = "";
		my $fcid = $fields[$header_idx{'FCID'}];
		my $lib_id = $fields[$header_idx{'Library ID'}];		
		my $matched_normal = defined($header_idx{'Matched normal'})? $fields[$header_idx{'Matched normal'}] : "";
		my $matched_rnaseq = defined($header_idx{'Matched RNA-seq lib'})? $fields[$header_idx{'Matched RNA-seq lib'}] : "";
		$matched_normal = &formatSampleID($matched_normal) if ($matched_normal);
		$matched_rnaseq = &formatSampleID($matched_rnaseq) if ($matched_rnaseq);		
		my $enhance_pipe = defined($header_idx{'EnhancePipe'})? $fields[$header_idx{'EnhancePipe'}] : "";
		my $peak_calling = defined($header_idx{'PeakCalling'})? $fields[$header_idx{'PeakCalling'}] : "";		
		if (defined($lib_id)) {
			$illumina_id = $lib_id;
		}
		if ($fcid && $fcid ne "" && $fcid ne "0" && $fcid ne "#N/A!") {
			$illumina_id = $lib_id."_".$fcid;
		}
		
		my $bio_type = "";
		my $material_type = "";
		my $tissue_cat = "";
		if ($type =~ /DNA/i) {
			$material_type = "DNA";
		}
		if ($type =~ /RNA/i) {
			$material_type = "RNA";
		}
		if ($type =~ /blood/i) {
			$tissue_cat = "normal";
		}
		if ($type =~ /cell line/i) {
			$tissue_cat = "cell line";
		}
		if ($type =~ /xeno/i) {
			$tissue_cat = "xeno";
		}
		if ($type =~ /tumor/i) {
			$tissue_cat = "tumor";
		}
		if ($type =~ /normal/i) {
			$tissue_cat = "normal";
		}


		my $original_exp_type = $fields[$header_idx{'Type of sequencing'}];
		next if (!$original_exp_type);
		my $exp_type = "";
		
		
		if ($original_exp_type =~ /C-il/) {
			$exp_type = "ChIPseq";
		}
		if ($original_exp_type =~ /Chip/) {
			$exp_type = "ChIPSeq";
		}
		if ($original_exp_type =~ /M-il/) {
			$exp_type = "Methylseq";
		}
		if ($original_exp_type =~ /T-il/) {
			$exp_type = "RNAseq";
		}
		if ($original_exp_type =~ /E-il/) {
			$exp_type = "Exome";
		}
		if ($original_exp_type =~ /P-il/) {
			$exp_type = "Panel";
		}
		if ($original_exp_type =~ /WG-il/) {
			$exp_type = "Whole Genome";
		}
		if ($original_exp_type =~ /WG-CGI/) {
			$exp_type = "Whole Genome";
		}		
		if ($original_exp_type =~ /CGI/) {
			$platform = "CGI";
		}
		
		next if ($exp_type eq "ChIPseq");		
		
		next if ($exp_type =~ /rejected/);

		next if ($exp_type eq "");

		my $diag = ucfirst($fields[$header_idx{'Diagnosis'}]);
		my $tissue_type = $diag;

		next if ( $tissue_type =~ /^[0-9]+$/ );
		next if ( $tissue_type =~ /^[0-9]+$/ );
		if (lc($tissue_type) eq 'normal tissue' || lc($tissue_type) eq 'normal' || lc($tissue_type) eq 'blood') {
			$diag = "Normal";
			if (lc($tissue_type) eq 'blood') {
				$tissue_type = "blood";
			} else {
				$tissue_type = $fields[$header_idx{'Anatomy/Cell Type'}];
				if ($tissue_type eq "") {
					$tissue_type = "NA";
				}
			}			
		}
		if ($tissue_type =~ /colon,/) {
			$tissue_type = "colon";
		}
		my $lib_type = "";
		if (defined($header_idx{'Enrichment step'})) {
			$lib_type = $fields[$header_idx{'Enrichment step'}];
		} else {
			$lib_type = $fields[$header_idx{'HiSeq RNA-seq library prep method'}];
		}
		$lib_type = "" if (!$lib_type);
		if ($lib_type =~ /access/i) {
			$lib_type = 'access';
		}
		if ($lib_type =~ /polyA/i) {
			$lib_type = 'polyA';
		}
		my $source = $fields[$header_idx{'Project'}];
		my $dataset = defined($header_idx{'Study Code'})? $fields[$header_idx{'Study Code'}]: "";
		my $ref = defined($header_idx{'SampleRef'})? $fields[$header_idx{'SampleRef'}]: "";
		my $sbj_notes = defined($header_idx{'Subject Notes'})? $fields[$header_idx{'Subject Notes'}]: ""; 
				
		my $alternate_id = defined($header_idx{'ALTERNATE_ID'})? $fields[$header_idx{'ALTERNATE_ID'}]: "";
		my $protocol_no = defined($header_idx{'Protocol no'})? $fields[$header_idx{'Protocol no'}]: "";
		my $cus_id = "";
		if (defined($header_idx{'patient_id'})) {
			$cus_id = $fields[$header_idx{'patient_id'}];
		} else {
			if (defined($header_idx{'custom ID'})) {
				$cus_id = $fields[$header_idx{'custom ID'}];
			}
		}
		
		my $relation = "self";
#		print "@fields\n";
#		print "$cus_id\n";
		if ($input_file =~ /Sequencing_Tracking_Master_db/i) {
			if ($cus_id =~ /.*\.(.*)/) {
				my $rel_str = $1;
				$relation = $rel_str if ($rel_str =~ /mother|father|brother|sister/i);		
			}
			if ($cus_id =~ /(.*?)\./) {
				$cus_id = $1;
			}			
			$cus_id =~ s/[\s\-()]//g;
		}
		
		my $field_idx = 1;
				
		my $prj = $fields[$header_idx{'Project'}];

		if ($cus_id eq "") {
			push(@errors, "$input_file\t$cus_id\tNo patient ID/custom ID information");
			$error="True";
		}
		if ($diag eq "") {
			push(@errors, "$input_file\t$cus_id\tNo diagnosis information");
			$error="True";
		}
		if ($prj eq "") {
			push(@errors, "$input_file\t$cus_id\tNo project information");
			$error="True";
		}
		if ($illumina_id eq "" && $exp_type ne "") {
			push(@errors, "$input_file\t$cus_id\tNo Library ID information(Library type: $exp_type)");
			$error="True";
		}		
		
		my $case_name = $default_case_id;
		my $sample_project = "";
		if (defined($header_idx{'Case Name'})) {
			$case_name = $fields[$header_idx{'Case Name'}];
		}
		
		if (!defined $case_name || $case_name eq "") {
			if ($sample_project ne "") {
				$case_name = $sample_project;
			} else {
				$case_name = $default_case_id;
			}
		} else {
			if ($sample_project ne "") {
				$case_name = $case_name.",".$sample_project;
			}			
		}
		my $data_path = "/data/khanlab/projects/working_DATA/";
		my $cmd = 'ssh helix.nih.gov "test -e '.$data_path.' && echo 1 || echo 0"';
		#my $res = readpipe($cmd);

		my $has_sample = 0;
		my $sample_id = "";
		#HC 01/06/2020. Replace patient_id with new one based on the patient ID mapping file
		if (exists $patient_mapping{$cus_id}) {
			if ($alternate_id eq "") {
				$alternate_id = $cus_id;
			}
			$cus_id = $patient_mapping{$cus_id};
		}
		try {
			if ($illumina_id ne "") {			
				my @fcids = split(/\|\|/, $fcid);
				if ($fcid eq "") {
					push @fcids, "";
				}
				foreach my $fid (@fcids) {
					if ($fid eq "") {
						$illumina_id = $lib_id;
					}
					else {
						$illumina_id = $lib_id."_".$fid;
					}
					$illumina_id =~ s/\s//;
					$has_sample = 1;
					if (!exists $samples{$illumina_id}) {
						#if type is RNAseq or normal then the matched sample is itself
						if ($exp_type eq "RNAseq") {
							$matched_rnaseq = $illumina_id;
						}
						if ($tissue_cat eq "normal") {
							$matched_normal = $illumina_id;
						}
						if ($exp_type eq "") {
							push(@errors, "$input_file\t$cus_id\tNo T-il/E-il/WG-il/WG-CGI information in ''Type of sequencing' column");
							$error="True";
						}
						if ($tissue_cat eq "") {
							push(@errors, "$input_file\t$cus_id\tNo normal/tumor information in 'Type' column");
							$error="True";
						}
						if ($tissue_type eq "") {
							push(@errors, "$input_file\t$cus_id\tNo Diagnosis (or Normal tissue's Anatomy/Cell Type) information");
							$error="True";
						}
						if ($material_type eq "") {
							push(@errors, "$input_file\t$cus_id\tNo DNA/RNA information in 'Type' column");
							$error="True";
						}
						$sth_smp->execute($illumina_id, $lib_id, $cus_id, $src_bio_id, $bio_id, $material_type, $exp_type, 'Illumina', $lib_type, $tissue_cat, $tissue_type, $source, $ref, $dataset, $data_path, '0', $matched_normal, '', $relation, $lib_id, $matched_rnaseq, $case_name, $enhance_pipe, $peak_calling, '');
						$samples{$illumina_id} = '';
						my $start_idx = defined($header_idx{'custom ID'})? $header_idx{'custom ID'} + 1 : 0;
						if ($start_idx == 0) {
							$start_idx = defined($header_idx{'Case Name'})? $header_idx{'Case Name'} + 1 : 0;
						}
						if ($start_idx != 0) {
							my $end_idx = $#headers;
							if (defined($header_idx{'patient_id'})) {
								$end_idx = $#headers - 1;
							}
							&saveDetail($start_idx, $end_idx, $illumina_id, \@headers, \@fields);
						}
						$sample_id = $illumina_id;

						#insert project information
						if ($prj ne "") {
							my @prjs = split(/,/, $prj);
							my %prj_names = ();
							foreach my $project_name (@prjs) {
								$project_name =~ s/^\s+|\s+$//g;
								next if ($project_name eq "");
								next unless (defined $project_name);
								if ($project_name eq "ClinOmics") {
									$project_name = "Clinomics";
								}
								if (exists $prj_names{$project_name}) {
									next;
								}
								$prj_names{$project_name} = '';
								$projects_in_master{$project_name} = '';
								my $project_id = (exists $projects{$project_name})? $projects{$project_name} : -1;
								if ($project_id == -1) {
									$sth_prj->execute($project_name, $project_name);			
									$sth_prj_id->execute($project_name);
									if (my @row = $sth_prj_id->fetchrow_array) {
										$project_id = $row[0];
									}
									$sth_prj_id->finish;			
									$projects{$project_name} = $project_id;
								}					
								$sth_prj_smp->execute($project_id, $cus_id, $illumina_id, $lib_id, $tissue_cat, $tissue_type, $lib_type, 'Illumina', $material_type, $exp_type);
							}
						}

					} else {
						#push(@errors, "$input_file\t$cus_id\tDuplicate sample ID: $illumina_id");
					}
				}
			}else{
				print "No illumina_id\n"  and <STDIN>   if ($verbose);
			}

			if ($cgi_sample_id ne "") {
				$sample_id = $cgi_sample_id;
				if($cus_id eq 'RMS2448'){
					print "$cus_id\n";
				}
				$sth_smp->execute($cgi_sample_id, $cgi_sample_id, $cus_id, $src_bio_id, $bio_id, $material_type, 'CGI', 'CGI', $lib_type, $tissue_cat, $tissue_type, $source, $ref, $dataset, $data_path, '0', $matched_normal, '', $relation, $cgi_sample_id, $matched_rnaseq, $case_name, $enhance_pipe, $peak_calling);
			}	else{
				print "No cgi_sample_id\n"  and <STDIN>  if ($verbose);
			}		
			
			my @cases = split(/,/, $case_name);
			#insert project information

			print "proj = $prj"  and <STDIN>  if ($verbose);
			if ($prj ne "") {
				my @prjs = split(/,/, $prj);
				foreach my $project_name (@prjs) {
					$project_name =~ s/^\s+|\s+$//g;
					next if ($project_name eq "");
					next unless (defined $project_name);
					if ($project_name eq "ClinOmics") {
						$project_name = "Clinomics";
					}
					$projects_in_master{$project_name} = '';
					my $project_id = (exists $projects{$project_name})? $projects{$project_name} : -1;
					if ($project_id == -1) {
						$sth_prj->execute($project_name, $project_name);			
						$sth_prj_id->execute($project_name);
						if (my @row = $sth_prj_id->fetchrow_array) {
							$project_id = $row[0];
						}
						$sth_prj_id->finish;			
						$projects{$project_name} = $project_id;
					}					
					#insert case information				
					foreach my $case (@cases) {						
						$case =~ s/^\s+|\s+$//g;
						next if ($case eq '');
						if (!exists $project_patients{$project_name}{$cus_id}{$case}) {
							$sth_prj_pat->execute($project_id, $cus_id, $case);
							
							$project_patients{$project_name}{$cus_id}{$case} = '';
						}		
					}				
				}
			}

			if ($sample_id ne "") {
				foreach my $case (@cases) {
					$case =~ s/^\s+|\s+$//g;
					print "case is empty!! ($case)...skipping\n" .join ("\n",@cases)."\n-------END\n"  and <STDIN>   if ($verbose and $case eq '') ;
					next if ($case eq '');
					if (!exists $sample_cases{$sample_id}{$cus_id}{$case}) {
						print "executing!!!$sample_id, $cus_id, $case\n" if ($verbose);
						$sth_smp_case->execute($sample_id, $cus_id, $case, '', '');
						$sample_cases{$sample_id}{$cus_id}{$case} = '';
					}elsif($verbose){
						print "did not insert into sample_cases because already exists??($sample_id||$cus_id||$case)\n" . Dumper (\$sample_cases{$sample_id}{$cus_id});<STDIN>;
					}
				}
			} else{
				print "IMPORTANT: Sample_id is empty"  and <STDIN>  if ($verbose);
				#push(@errors, "$input_file\t$cus_id\tNo sample ID");
			}

			#if ($has_sample) {


				if (!exists $patients{$cus_id}) {
					$sth_pat->bind_param(1, $cus_id);
					$sth_pat->bind_param(2, $diag);
					$sth_pat->bind_param(3, $prj);
					$sth_pat->bind_param(4, 'N');
					$sth_pat->bind_param(5, $alternate_id);
					$sth_pat->bind_param(6, $protocol_no);
					$sth_pat->bind_param(7, 'NA');
					$sth_pat->bind_param(8, 1);
					$sth_pat->execute();	
					$patients{$cus_id} = '';
				}
			#}
		} catch {
			#print "Error happened in file $input_file, patient: $cus_id\nDetail info: $_\n"
			push(@errors, "$input_file\t$cus_id\t$_"); 
		}
	}
	close(IN_FILE);	
}

sub formatSampleID {
	my ($sample_id) = @_;
	$sample_id = "" if ($sample_id eq ".");
	$sample_id =~ s/Sample_//;
	$sample_id =~ s/\/$//;
	$sample_id =~ s/_$//;
	return $sample_id;

}

sub saveDetail {	
	my ($start_idx, $end_idx, $id, $headers_ref, $fields_ref) = @_;	
	for (my $i=$start_idx; $i<=$end_idx; $i++) {		
		my @headers = @{$headers_ref};
		my @fields = @{$fields_ref};		
		next if (!$fields[$i]);
		next if ($fields[$i] eq "" || $fields[$i] eq "#N/A!" || $fields[$i] eq "#N/A");		
		next if ($headers[$i] eq "Row No");
		chomp $fields[$i];
		chomp $headers[$i];
		$sth_smp_dtl->bind_param(1, $id);
		$sth_smp_dtl->bind_param(2, $headers[$i]);
		$sth_smp_dtl->bind_param(3, $fields[$i]);
		$sth_smp_dtl->execute();
				
	}

}

#check library type
$sth_check_lib_type->execute();
while (my @row = $sth_check_lib_type->fetchrow_array) {
	my $sample_id = $row[0];
	push(@errors, "NA\t$sample_id\tEnrichment Step (library type) of tumor/normal pair does not match");
}
$sth_check_lib_type->finish;
#check normal samples
$sth_check_normal->execute();
while (my @row = $sth_check_normal->fetchrow_array) {
	my $sample_id = $row[0];
	my $normal_sample = $row[1];
	push(@errors, "NA\t$sample_id\tMatched normal $normal_sample is ambiguous");
}
$sth_check_normal->finish;
#check rnaseq samples
$sth_check_rnaseq->execute();
while (my @row = $sth_check_rnaseq->fetchrow_array) {
	my $sample_id = $row[0];
	my $rnaseq_sample = $row[1];
	push(@errors, "NA\t$sample_id\tMatched RNAseq $rnaseq_sample is ambiguous");
}
$sth_check_rnaseq->finish;


my $num = $dbh->do("update patients set is_cellline = 'Y' where exists(select * from samples where samples.patient_id=patients.patient_id and samples.tissue_cat='cell line')");
print "updated $num patients set is_cellline\n";
$num = $dbh->do("update patients p set case_list = (select listagg(case_name,',') within group( order by case_name ) as case_list from (select distinct patient_id, case_name from samples ) p2 where p.patient_id=p2.patient_id group by patient_id)");
print "updated $num patients set case_id\n";
$num = $dbh->do("update patients p set project_name = (select listagg(name,',') within group( order by name ) as project_name from (select distinct p1.patient_id, name from project_patients p1, projects p2 where p1.project_id=p2.id ) pp where p.patient_id=pp.patient_id group by patient_id)");
print "updated $num patients set project_name\n";
$num = $dbh->do("update projects set ispublic=1 where name in ('Omics')");
print "updated $num project set isPublic\n";
$num = $dbh->do("update samples s1 set normal_sample=(select sample_id from samples s2 where s1.normal_sample=s2.sample_name) where (select count(*) from samples s2 where s1.normal_sample=s2.sample_name)=1 and normal_sample is not null");
print "updated $num samples set normal_sample\n";
$num = $dbh->do("update samples s1 set rnaseq_sample=(select sample_id from samples s2 where s1.rnaseq_sample=s2.sample_name) where (select count(*) from samples s2 where s1.rnaseq_sample=s2.sample_name)=1 and rnaseq_sample is not null");
print "updated $num set rnaseq_sample\n";
#$dbh->do("update sample_cases s set case_id=(select distinct c.case_id from cases c where c.status <> 'failed' and c.case_name=s.case_name and c.patient_id=s.patient_id)");
my $content = "";
my $json;
my $email_file = dirname(__FILE__)."/../../config/email_list.json";
#my $email_file = dirname(__FILE__."../");
# print $email_file."\n";
{
  local $/; #Enable 'slurp' mode
  open my $fh, "<", $email_file;
  $json = <$fh>;
  close $fh;
}
my $data = decode_json($json);
my $email_list=$data->{'master'};
my $modified_file_list = join(",", @modified_files);
if ($#errors == -1) {
	$content = "<H4>Upload to $database_name database successful!</H4><H4>The following files have been modified: <span style='color:red'>$modified_file_list</span></H4>";
	$dbh->commit();
	&sendEmail($content, $database_name, $email_list);
	
	if ($update_case) {
		print "Updating cases\n";
		eval{
			system("$script_dir/updateVarCases.pl");
		};
		if ($?||$@){
			&sendEmail("Could not successfully run updateVarCases.pl after successfully uploading to the database $modified_file_list\nNote:  You will need to refresh MV PROCESSED_SAMPLE_CASES after rerunning if you run this out of $0\n",'','vuonghm@mail.nih.gov');
		}
		$dbh->do("BEGIN Dbms_Mview.Refresh('PROCESSED_SAMPLE_CASES','C');END;");
	}
}
else {
	$dbh->rollback();
	$content = "<H4>Upload to $database_name database failed!</H4><H4>The following files have been modified: <span style='color:red'>$modified_file_list</span></H4>".'<table id="errlog" border=1 cellspacing="2" width="80%">
    <thead><tr><th>Input file</th><th>Patient/Sample ID</th><th>Error</th></tr></thead>';

	foreach my $err (@errors) {
		$content .= "<tr>";
		my @fields = split(/\t/, $err);
		foreach my $field (@fields) {
			$content .= "<td>$field</td>";
		}
	}
	$content .= "</tr></tbody></table>";
       &sendEmail($content, $database_name,$email_list);
    exit;#2019090
}

#$dbh->do("BEGIN Dbms_Mview.Refresh('PROJECT_SAMPLES','C');END;");
$dbh->do("BEGIN Dbms_Mview.Refresh('USER_PROJECTS','C');END;");

$sth_prj_rnaseq_smp = $dbh->prepare("select project_id,sample_id from project_samples where exp_type='RNAseq' order by project_id,sample_id");

$sth_prj_rnaseq_smp->execute();
while (my @row = $sth_prj_rnaseq_smp->fetchrow_array) {
	my $project_id = $row[0];
	my $sample_id = $row[1];
	push @{$new_project_samples{$project_id}}, $sample_id;	
}
$sth_prj_rnaseq_smp->finish;

my @diff_projects = ();
foreach my $project_id (keys %old_project_samples) {
	#print $project_id."\n";
	my @old_samples = @{$old_project_samples{$project_id}};
	my @new_samples = @{$new_project_samples{$project_id}};
	#print $project_id."\n";
	if ($#old_samples != $#new_samples) {
		push @diff_projects, $project_id;
	} else {
		for (my $i=0;$i<=$#old_samples;$i++) {
			if ($old_samples[$i] ne $new_samples[$i]) {
				push @diff_projects, $project_id;
				print "pushing old samples $project_id\n";
				last;
			}
		}
	}
}

foreach my $project_id(@diff_projects) {
	print "Refreshing RNAseq project DATA for project $project_id\n";
	print "$script_dir/../preprocessProjectMaster.pl -p $project_id\n";
	eval{
		#system("$script_dir/../preprocessProjectMaster.pl -p $project_id");
	};
	if ($@||$?){
		&sendEmail("Error running preprocessProjectMaster.pl for $project_id\n$@\n$?\n", $database_name, 'chouh@nih.gov');
	}
}

print "commiting...";
$dbh->commit();
$dbh->disconnect();
print "done on $sid\n";

#find orphan projects
if ($rm_orphan_prj) {
	print "Orphan projects:\n";
	while (my ($project_name, $project_id) = each %projects) {
		if (!exists $projects_in_master{$project_name}) {
			print "$project_id\t$project_name\n";
			system("$script_dir/deleteProject.pl -p $project_id -r");
		}
	}
}

sub sendEmail {
	my ($content, $database_name, $recipient) = @_;
	my $subject   = "OncogenomicsDB master file upload status";
	my $sender    = 'oncogenomics@mail.nih.gov';
	#my $recipient = 'hsien-chao.chou@nih.gov, rajesh.patidar@nih.gov, manoj.tyagi@nih.gov, yujin.lee@nih.gov, wangc@mail.nih.gov';
#	if ($database_name eq "development") {
#		$recipient = 'vuonghm@mail.nih.gov';
#	}
	my $mime = MIME::Lite->new(
	    'From'    => $sender,
	    'To'      => $recipient,
	    'Subject' => $subject,
	    'Type'    => 'text/html',
	    'Data'    => $content,
	);

	$mime->send();
}



