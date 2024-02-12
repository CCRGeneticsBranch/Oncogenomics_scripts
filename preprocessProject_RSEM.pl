#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Cwd 'abs_path';
use Getopt::Long qw(GetOptions);
use File::Basename;
require(dirname(abs_path($0))."/lib/Onco.pm");

my $project_id;
my $out_dir;
my $type;
my $level;
my $matrix_file;
my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -p  <integer> project id
  -t  <string>  type
  -l  <string>  level
  -o  <string>  output directory
  -m  <string>  matrix file
  
__EOUSAGE__
my $r_path = getConfig("R_PATH");
$ENV{'PATH'}=$r_path.$ENV{'PATH'};#Ubuntu16
$ENV{'R_LIBS'}=getConfig("R_LIBS");#Ubuntu16

GetOptions (
  'p=i' => \$project_id,
  't=s' => \$type,
  'l=s' => \$level,
  'o=s' => \$out_dir,
  'm=s' => \$matrix_file,
);

my $script_dir = abs_path(dirname(__FILE__));
my $data_dir = abs_path($script_dir."/../../../onco.data/ProcessedResults");
my $coding_list = abs_path($script_dir."/../storage/data/coding_list.tsv");

if (!$project_id) {
	die "Some parameters are missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();


#my %normal_list = ();
#my $normal_list_file = "$script_dir/backend/normal_list.tsv";
#open(NORMAL_FILE, "$normal_list_file") or die "Cannot open file $normal_list_file";
#while (<NORMAL_FILE>) {
#	chomp;
#	my @fields = split(/\t/);
#	if ($#fields == 2) {
#		$normal_list{$fields[0]} = [$fields[1], $fields[2]];
#	}
#}
#close(NORMAL_FILE);
my $sql_insert_stat = "insert into /*+ APPEND */ PROJECT_STAT values(?,?,?,?,?,?,?,?)";
my $sql_delete_project_value = "delete PROJECT_VALUES where project_id=? and target_type=? and target_level=? and value_type=?";
my $sql_insert_project_value = "insert into /*+ APPEND */ PROJECT_VALUES values(?,?,?,?,?,?,?,?)";
my $sql_delete_project_expression = "delete PROJECT_EXPRESSION where project_id=? and target_type=? and target_level=? and value_type=?";
my $sql_insert_project_expression = "insert into /*+ APPEND */ PROJECT_EXPRESSION values(?,?,?,?,?)";

my $sth_insert_stat = $dbh->prepare($sql_insert_stat);
my $sth_delete_project_value = $dbh->prepare($sql_delete_project_value);
my $sth_insert_project_value = $dbh->prepare($sql_insert_project_value);
my $sth_delete_project_expression = $dbh->prepare($sql_delete_project_expression);
my $sth_insert_project_expression = $dbh->prepare($sql_insert_project_expression);

my $value_type = "exp";
my %sample_name_mapping = ();
my %sample_id_mapping = ();
my %sample_alias_mapping = ();
my %sample_id_alias_mapping = ();

&process($type, $level);
$dbh->disconnect();

sub process {
	my ($type, $level) = @_;
	#my $sql = "select s.sample_id, s.sample_name,e.target,e.gene,e.symbol,e.value from sample_values e, project_samples s where s.exp_type='RNAseq' and e.target_type='$type' and e.target_level = '$level' and s.project_id=$project_id and s.sample_id=e.sample_id";
	my $sql_prj = "select name, version from projects where id=$project_id";
	#my $sql_samples = "select distinct s.sample_id, s.sample_name, c.patient_id, c.case_id, path, library_type, tissue_type from project_samples s,cases c where c.patient_id = s.patient_id and s.exp_type='RNAseq' and s.project_id=$project_id order by s.sample_id";
	my $sql_samples = "select distinct s.sample_id, s.sample_name, s.sample_alias, c.patient_id, c.case_id, c.path, s.library_type, s.tissue_type from project_samples p,samples s, sample_cases sc, cases c where sc.sample_id = s.sample_id and s.exp_type='RNAseq' and p.project_id=$project_id and p.sample_id=s.sample_id and sc.case_id=c.case_id and sc.patient_id=c.patient_id order by s.sample_id";
	#my $sql_coding = "select distinct symbol from gene where type='protein-coding'";
	my %data = ();
	my %targets = ();
	my %lib_types = ();
	my %tissue_types = ();
	my %coding_symbols = ();
	my %sample_names = ();	
	my $start = time;
	#print "$sql_samples\n";
	#print "$sql_coding\n";
	my $sth_prj = $dbh->prepare($sql_prj);
	my $sth_samples = $dbh->prepare($sql_samples);
	#my $sth_coding = $dbh->prepare($sql_coding);

	$sth_prj->execute();
	my $project_name;

	my $version = "";
	($project_name, $version) = $sth_prj->fetchrow_array;
	if (!$version) {
		$version = "19";
	}

	$sth_prj->finish();
	if (!$project_name) {
		print "Project $project_id not found!\n";
		return;
	}
	print "=> Processing project: $project_name..., level: $level\n";
	#$sth_coding->execute();
	#while (my ($symbol) = $sth_coding->fetchrow_array) {
		#save coding symbol to hash
	#	$coding_symbols{$symbol} = '';		
	#}
	#$sth_coding->finish();

	my $exp_list_file = "$out_dir/exp_list-$type-$level.tsv";
	open(EXP_LIST_FILE, ">$exp_list_file") or die "Cannot write file $exp_list_file";
	
	#my %sample_id_list = (); 
	#foreach my $sample_id (keys %normal_list) {
	#	my $sample_name = $normal_list{$sample_id}[0];
	#	$sample_name_mapping{$sample_name} = $sample_id;
	#	my $path = $script_dir."/../storage/ProcessedResults/".$normal_list{$sample_id}[1];	
	#	my $rdsfile = &getRDSFile($path, $sample_id, $sample_name, $type, $level);
	#	if ($rdsfile ne "") {
	#		$sample_id_list{$sample_id} = '';
	#		print RDS_LIST_FILE "$sample_id\t$sample_name\t$rdsfile\n";
	#	}
	#}
	$sth_samples->execute();
	my $flag = 1;
	my $genes_file="$out_dir/genes-$type-$level.tsv";
	my $total_samples = 0;	
	while (my ($sample_id, $sample_name, $sample_alias, $patient_id, $case_id, $path, $lib_type, $tissue_type) = $sth_samples->fetchrow_array) {
		#save coding symbol to hash
		next if ($patient_id eq "CL0049" || $patient_id eq "CL0082" || $patient_id eq "CL0263" || $patient_id eq "CL0280");
		my $path = $data_dir."/$path/$patient_id/$case_id";		
		$sample_alias_mapping{$sample_alias} = $sample_id;		
		$sample_id_mapping{$sample_id} = $sample_name;
		$sample_id_alias_mapping{$sample_id} = $sample_alias;
		$lib_types{$sample_id} = (lc($lib_type) eq "polya");
		if ( $lib_type =~ /polya/i ) {
			$lib_type = "polya";
		}
		if ( $lib_type =~ /ribo/i ) {
			$lib_type = "ribozero";
		}
		if ( $lib_type =~ /access/i ) {
			$lib_type = "access";
		}
		
		$tissue_types{$sample_id} = $tissue_type;
		my $expfile = &getExpFile($path, $sample_id, $sample_name, $type, $level);
		if ($expfile ne "" ) {
			if (!exists $sample_name_mapping{$sample_name}) {				
				$sample_name_mapping{$sample_name} = $sample_id;	
				print EXP_LIST_FILE "$sample_id\t$sample_name\t$expfile\t$lib_type\t$tissue_type\n";
				my $count_file = $expfile.".count.txt";
				my $tpm_file = $expfile.".tpm.txt";				
				#if ( !-e $count_file) {
					system("cut -f5 $expfile > $count_file");
				#}
				#if ( !-e $tpm_file) {
					system("cut -f6 $expfile > $tpm_file");
				#}
					
				if ($flag) {
					system("cut -f1 $expfile > $genes_file");
					$flag = 0;
				}
				$total_samples++;	
				#my $merged_file="$out_dir/count.mat";
				#if (! -e $merged_file ) {
				#	system("cut -f1 $expfile > $merged_file");
				#} else {
					#system("paste $merged_file $count_file > $merged_file");
				#}

					
				#my $wc = readpipe("wc -l $count_file | cut -d' ' -f1");
				#if ($wc == 57774) {
				#	print $expfile."\n";
				#}
				#$sample_id_list{$sample_id} = '';
			}
		} else {
			print("RSEM file not found: $path. Sample: $sample_id\n");
			#print "RDS file not found!: $path $case_id$ sample_id\n";
		}
		
		#if ($total_samples == 200) {
		#	last;
		#}
	}

	my $dry_run = 0;
	close(EXP_LIST_FILE);	
	$sth_samples->finish();
	print("Total samples: $total_samples\n");
	my $size = keys %sample_name_mapping;
	if ( $size == 0 ) {
		print "No RNAseq data\n";
		$dbh->disconnect();
		exit(0);
	}

	$dbh->do("update projects set status=1 where id=$project_id");
	$dbh->commit();	

	my $type_str = ($type eq "refseq")? "UCSC" : "ENSEMBL";
	my $level_str = ($level eq "gene")? "gene" : "transcript";
	#my $annotation_file = "$script_dir/../storage/data/AnnotationRDS/annotation_".$type_str."_".$level_str."_38.RDS";
	#my $annotation_file = "$script_dir/../storage/data/AnnotationRDS/annotation_".$type_str."_".$level_str."_".$version.".RDS";
	my $annotation_file = "$script_dir/../storage/data/AnnotationRDSRSEM/annotation_${type_str}_${level_str}_${version}.RDS";
	print($annotation_file."\n");
	my $normalized_file = "$type-$level";
	print "\nUse annotation file: $annotation_file\n";
	my $cmd = "$r_path/Rscript $script_dir/tmmNormalize_RSEM.r $exp_list_file $genes_file $coding_list $annotation_file $level $out_dir/ $normalized_file";
	print "TMM normalizing...\n";
	print "Command: $cmd\n";
	if (!$dry_run) {
		system($cmd);	
	}		

	my $duration = time - $start;
	print "time (TMM): $duration s\n";
	
	print "===> Processing type: $type, level: $level ...\n";
	$start = time;
		
	my @norm_types = ('tmm-rpkm','tpm');
	#my @library_types = ('all','polya','nonpolya');
	#my @norm_types = ('tmm-rpkm');
	#my @library_types = ('all');
	

	my $exp_file = "$out_dir/$type-${level}.coding";
	if ($matrix_file) {
		system("cp $matrix_file $exp_file.tmm-rpkm.tsv");
	}

	foreach my $norm_type (@norm_types) {
		print "inserting $norm_type\n";
		if (!$dry_run) {
			
			&insertProjectValues($exp_file, $norm_type);
		}
	}

	$duration = time - $start;
	print "time (Insert DB): $duration s\n";
	$start = time;
	#save value to text file
	my $min_value = 0;	

	$dbh->commit();

	#run R to calculate stats
	#my $stat_file = "$out_dir/$type-$level-stat";
	#my $loading_file = "$out_dir/$type-$level-loading";
	#my $coord_file = "$out_dir/$type-$level-coord";
	#my $rds_file = "$out_dir/$type-$level-coding";
	#my $coord_tmp_file = "$out_dir/$type-$level-coord_tmp";
	#my $std_file = "$out_dir/$type-$level-std";
		
	#my $file_prefix = "$out_dir/$type-$level";
	#foreach my $norm_type (@norm_types) {
		#foreach my $library_type (@library_types) {
		#print("runStat: $library_type, $norm_type\n");
			#&runStat($library_type, $norm_type);			
		#}
	#}
	
	#&runStat($exp_coding_tpm_file, $stat_file_tpm, $loading_file_tpm, $coord_tmp_file_tpm, $std_file_tpm, $rds_file_tpm, $coord_file_tpm, "tpm");

	$duration = time - $start;
	print "time(runStat): $duration s\n";
	$dbh->do("update projects set status=2 where id=$project_id");
	$dbh->commit();	
	$dbh->disconnect();
	system("mkdir -p $out_dir/cor");
	system("mkdir -p $out_dir/survival");
}

sub runStat {
	#my ($exp_coding_file, $stat_file, $loading_file, $coord_tmp_file, $std_file, $rds_file, $coord_file, $value_type) = @_;
	my ($library_type, $norm_type) = @_;

	my $prefix = "$out_dir/$type-$level";
	my $stat_file = "$prefix-stat.$library_type.$norm_type.tsv";
	my $coord_tmp_file = "$prefix-coord_tmp.$library_type.$norm_type.tsv";
	my $coord_file = "$prefix-coord.$library_type.$norm_type.tsv";
	my $z_coord_tmp_file = "$prefix-coord_tmp.$library_type.$norm_type.zscore.tsv";
	my $z_coord_file = "$prefix-coord.$library_type.$norm_type.zscore.tsv";
	my $cmd = "Rscript ".dirname($0)."/preprocessProject.r $prefix $library_type $norm_type";
	my $input_file = "$prefix-coding.$library_type.$norm_type.tsv";
	if ($level ne "gene" && -e $input_file) {
		$cmd = "Rscript ".dirname($0)."/preprocessProject.r $prefix $library_type $norm_type";
	}
	print($cmd."...\n");
	system($cmd);
	print("done\n");
	#save stats
	if (-e $stat_file) {
		my $sth_insert_stat = $dbh->prepare($sql_insert_stat);
		open(STATFILE, $stat_file) or die "Cannot open file $stat_file";

		my $row_count = 0;
		while(<STATFILE>) {
				chomp;
				my ($target, $mean, $std, $median) = split(/\s+/);
				$target =~ s/"//g;
				if ($std eq 'NA') {
					$std = 0;
				}
				#$sth_insert_stat->execute($project_id, $target, $type, $level, $value_type, $mean, $std, $median);
				$row_count++;
				#if ($row_count % 500 == 0) {
				#	$row_count = 0;
				#	$dbh->commit();		
				#}
		}			
		close(STATFILE);
	}

	if ($level eq "gene") {
		#fix the sample id in corrd file (R will change them)
		if (-e $coord_tmp_file) {	
			open(COORD_FILE, ">$coord_file") or die "Cannot open file $coord_file";
			open(COORD_TMP_FILE, $coord_tmp_file) or die "Cannot open file $coord_tmp_file";
			my $i = 0;
			while(<COORD_TMP_FILE>) {
					chomp;
					my @fields = split(/\s+/);
					print COORD_FILE join("\t", @fields)."\n";
			}
			close(COORD_FILE);
			close(COORD_TMP_FILE);
			system("rm $coord_tmp_file");
		}

		if (-e $z_coord_tmp_file) {	
			open(COORD_FILE, ">$z_coord_file") or die "Cannot open file $z_coord_file";
			open(COORD_TMP_FILE, $z_coord_tmp_file) or die "Cannot open file $z_coord_tmp_file";
			my $i = 0;
			while(<COORD_TMP_FILE>) {
					chomp;
					my @fields = split(/\s+/);
					print COORD_FILE join("\t", @fields)."\n";
			}
			close(COORD_FILE);
			close(COORD_TMP_FILE);
			system("rm $z_coord_tmp_file");
		}
	}
}

sub insertProjectValues {
	my ($exp_file, $norm_type) = @_;
	$exp_file = $exp_file.".${norm_type}.tsv";
	open(FILE, "$exp_file") or die "Cannot open file $exp_file";
	
	my $header = <FILE>;
	chomp $header;
	my @sorted_samples = split(/\t/, $header);
	my @sample_ids = ();
	my @sample_names = ();
	my @sample_alias_list = ();
	#splice(@sorted_samples, 0, 1);
	$sth_delete_project_expression->execute($project_id, $type, $level, $norm_type);
	foreach my $sample_id (@sorted_samples) {
		next if ($sample_id eq "");		
		my $sample_alias;
		if ($matrix_file && $norm_type eq "tmm-rpkm") {
			$sample_alias = $sample_id;
			chomp $sample_alias;
			$sample_id = $sample_alias_mapping{$sample_alias};
			if (!$sample_id) {
				print "alias: $sample_alias not found in DB\n";
				next;
			}			
		}

		my $sample_name = $sample_id_mapping{$sample_id};
		if (!$sample_name) {
			$sample_name = $sample_id;
			$sample_id = $sample_name_mapping{$sample_name};
			if (!$sample_id) {
				print "sample name: $sample_name not found!\n";
				next;
			}
		}
		if (!$sample_alias) {
			$sample_alias = $sample_id_alias_mapping{$sample_id};
		}
		push @sample_ids, $sample_id;
		push @sample_names, $sample_name;
		push @sample_alias_list, $sample_alias;

		$sth_insert_project_expression->execute($project_id, $sample_id, $type, $level, $norm_type);
	}
	#my $sample_name_list = join("\t", @sorted_samples);
	my $sample_name_list = join("\t", @sample_alias_list);
	$sth_delete_project_value->execute($project_id, $type, $level, $norm_type);	
	$sth_insert_project_value->execute($project_id, "_list", "_list", "_list", $type, $level, $norm_type, join(",", @sample_ids));
	#my $sample_list = join("\t", @sorted_samples);
	my $sample_alias_list_str = join("\t", @sample_alias_list);

	while(<FILE>) {
		chomp;
		my @fields = split(/\t/);
		if ($#fields > 1) {
			my $target = $fields[0];
			my $gene = $fields[0];
			my $symbol = $fields[0];
			splice(@fields, 0, 1);
			my $value_list = join(",", @fields);
			my @value_log_list = ();
			my $sum = 0;
			my $i = 0;
			foreach my $value (@fields) {
				#my $new_value = log($value + 1)/log(2);
				if ($value eq "NA") {
					print "$symbol in $exp_file has NA\n";
				} else {
					my $new_value = sprintf("%.2f", $value);
					$sum += $new_value;				
					push @value_log_list, $new_value;
				}
				$i++;
			}
			
			#if ($sum > 0) {
			#	print FILE_CODING_ALL "$symbol\t".join("\t", @value_log_list)."\n";
			#}
			$sth_insert_project_value->execute($project_id, $target, $gene, $symbol, $type, $level, $norm_type, $value_list); 
		}
	}
	close(FILE);	
}


sub insertProjectValues_old {
	my ($exp_file, $count_file, $exp_coding_file, $norm_type, $coding_symbols_ref, $lib_types_ref, $tissue_type_ref) = @_;
	my %coding_symbols = %$coding_symbols_ref;
	my %lib_types = %$lib_types_ref;
	my %tissue_types = %$tissue_type_ref;
	$exp_file = "$exp_file.$norm_type.tsv";

	open(FILE_CODING_COUNT_ALL, ">$exp_coding_file.count.tsv") or die "Cannot open file $exp_coding_file.all.count.tsv";
	open(FILE_CODING_ALL, ">$exp_coding_file.all.$norm_type.tsv") or die "Cannot open file $exp_coding_file.all.$norm_type.tsv";
	open(FILE_CODING_POLYA, ">$exp_coding_file.polya.$norm_type.tsv") or die "Cannot open file $exp_coding_file.polya.$norm_type.tsv";
	open(FILE_CODING_NONPOLYA, ">$exp_coding_file.nonpolya.$norm_type.tsv") or die "Cannot open file $exp_coding_file.nonpolya.$norm_type.tsv";
	open(FILE, "$exp_file") or die "Cannot open file $exp_file";
	open(FILE_COUNT, "$count_file") or die "Cannot open file $count_file";
	
	my $header = <FILE>;
	chomp $header;
	my @sorted_samples = split(/\t/, $header);
	#splice(@sorted_samples, 0, 1);
	my @sample_ids = ();
	my @sample_names = ();
	my %selected_cols = ();
	my @lib_type_list = ();
	my @polya_samples = ();
	my @nonpolya_samples = ();
	my @all_tissue_types = ();
	my @polya_tissue_types = ();
	my @nonpolya_tissue_types = ();
	my @sample_alias_list = ();
	$sth_delete_project_expression->execute($project_id, $type, $level, $norm_type);
	foreach my $sample_id (@sorted_samples) {
		next if ($sample_id eq "");		
		my $sample_alias;
		if ($matrix_file && $norm_type eq "tmm-rpkm") {
			$sample_alias = $sample_id;
			chomp $sample_alias;
			$sample_id = $sample_alias_mapping{$sample_alias};
			if (!$sample_id) {
				print "alias: $sample_alias not found in DB\n";
				next;
			}			
		}

		my $sample_name = $sample_id_mapping{$sample_id};
		if (!$sample_name) {
			$sample_name = $sample_id;
			$sample_id = $sample_name_mapping{$sample_name};
			if (!$sample_id) {
				print "sample name: $sample_name not found!\n";
				next;
			}
		}
		if (!$sample_alias) {
			$sample_alias = $sample_id_alias_mapping{$sample_id};
		}
		my $is_polya = $lib_types{$sample_id};
		my $tissue_type = $tissue_types{$sample_id};
		push @all_tissue_types, $tissue_type;
		push @lib_type_list, $is_polya;
		push @sample_ids, $sample_id;
		push @sample_names, $sample_name;
		push @sample_alias_list, $sample_alias;

		if ($is_polya) {
			#push @polya_samples, $sample_name;
			push @polya_samples, $sample_alias;
			push @polya_tissue_types, $tissue_type;
		} else {
			#push @nonpolya_samples, $sample_name;
			push @nonpolya_samples, $sample_alias;
			push @nonpolya_tissue_types, $tissue_type;
		}
		$sth_insert_project_expression->execute($project_id, $sample_id, $type, $level, $norm_type);
	}
	#my $sample_name_list = join("\t", @sorted_samples);
	my $sample_name_list = join("\t", @sample_alias_list);
	my $polya_sample_name_list = join("\t", @polya_samples);
	my $nonpolya_sample_name_list = join("\t", @nonpolya_samples);
	my $tissue_type_list = join("\t", @all_tissue_types);
	my $polya_tissue_type_list = join("\t", @polya_tissue_types);	
	my $nonpolya_tissue_type_list = join("\t", @nonpolya_tissue_types);
	$sth_delete_project_value->execute($project_id, $type, $level, $norm_type);	
	$sth_insert_project_value->execute($project_id, "_list", "_list", "_list", $type, $level, $norm_type, join(",", @sample_ids));
	#my $sample_list = join("\t", @sorted_samples);
	my $sample_alias_list_str = join("\t", @sample_alias_list);

	print FILE_CODING_ALL "\t$sample_alias_list_str\n";
	print FILE_CODING_POLYA "\t$polya_sample_name_list\n";
	print FILE_CODING_NONPOLYA "\t$nonpolya_sample_name_list\n";
	print FILE_CODING_ALL "Diagnosis\t$tissue_type_list\n";
	print FILE_CODING_POLYA "Diagnosis\t$polya_tissue_type_list\n";
	print FILE_CODING_NONPOLYA "Diagnosis\t$nonpolya_tissue_type_list\n";
	print FILE_CODING_COUNT_ALL "\t$sample_alias_list_str\n";
	while(<FILE_COUNT>) {
		chomp;
		my @fields = split(/\t/);
		if ($#fields > 1) {
			my $symbol = $fields[0];
			if (exists $coding_symbols{$symbol}) {
				print FILE_CODING_COUNT_ALL "$_\n";
			}
		}
	}
	close(FILE_CODING_COUNT_ALL);
	close(FILE_COUNT);
	while(<FILE>) {
		chomp;
		my @fields = split(/\t/);
		if ($#fields > 1) {
			my $target = $fields[0];
			my $gene = $fields[0];
			my $symbol = $fields[0];
			splice(@fields, 0, 1);
			my $value_list = join(",", @fields);
			my @value_log_list = ();
			my @polya_value_log_list = ();
			my @nonpolya_value_log_list = ();
			my $sum = 0;
			my $sum_polya = 0;
			my $sum_nonpolya = 0;
			my $i = 0;
			foreach my $value (@fields) {
				#my $new_value = log($value + 1)/log(2);
				my $new_value = sprintf("%.2f", $value);
				if ($lib_type_list[$i]) {
					$sum_polya += $new_value;				
					push @polya_value_log_list, $new_value;
				} else {
					$sum_nonpolya += $new_value;				
					push @nonpolya_value_log_list, $new_value;
				}
				$sum += $new_value;				
				push @value_log_list, $new_value;
				$i++;
			}
			if (exists $coding_symbols{$symbol}) {
				if ($sum > 0) {
					print FILE_CODING_ALL "$symbol\t".join("\t", @value_log_list)."\n";
				}
				if ($sum_polya > 0) {
					print FILE_CODING_POLYA "$symbol\t".join("\t", @polya_value_log_list)."\n";
				}
				if ($sum_nonpolya > 0) {
					print FILE_CODING_NONPOLYA "$symbol\t".join("\t", @nonpolya_value_log_list)."\n";
				}
				$sth_insert_project_value->execute($project_id, $target, $gene, $symbol, $type, $level, $norm_type, $value_list); 
			}			
		}
	}
	close(FILE);
	close(FILE_CODING_ALL);
	close(FILE_CODING_POLYA);
	close(FILE_CODING_NONPOLYA);
	if ($#sorted_samples == 0) {
		system("rm $exp_coding_file.all.$norm_type.tsv");
	}
	if ($#polya_samples == 0) {
		system("rm $exp_coding_file.polya.$norm_type.tsv");
	}
	if ($#nonpolya_samples == 0) {
		system("rm $exp_coding_file.nonpolya.$norm_type.tsv");
	}	
}

sub getExpFile {
	my ($path, $sample_id, $sample_name, $type, $level) = @_;
	my $level_str = ($level eq "gene")? "gene" : "transcript";
	#my $suffix = ".$level_str.fc.RDS";
	my $suffix = ($type eq "refseq")? ".rsem_UCSC.genes.results" : ".rsem_ENS.genes.results";
	my $folder = ($type eq "refseq")? "RSEM_UCSC" : "RSEM_ENS";
	my $sample_file = "$path/Sample_$sample_id/$folder/Sample_$sample_id$suffix";	
	if ( -e $sample_file) {
		return $sample_file;
	}
	$sample_file = "$path/Sample_$sample_name/$folder/Sample_$sample_name$suffix";	
	if ( -e $sample_file) {
		return $sample_file;
	}
	$sample_file = "$path/$sample_id/$folder/$sample_id$suffix";
	#print "$sample_file\n";
	if ( -e $sample_file) {
		return $sample_file;
	}
	$sample_file = "$path/$sample_name/$folder/$sample_name$suffix";
	if ( -e $sample_file) {
		return $sample_file;
	}
	#for Manoj
	if ($type eq "ensembl")	{		
		my $sample_file = "$path/$sample_name/RSEM/$sample_name$suffix";	
		if ( -e $sample_file) {
			return $sample_file;
		}
	}	

	return "";			
}

sub formatDir {
    my ($dir) = @_;
    if ($dir !~ /\/$/) {
        $dir = $dir."/";
    }
    return $dir;
}
