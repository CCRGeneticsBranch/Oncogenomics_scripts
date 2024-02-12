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
my $type="ensembl";
my $level="gene";
my $matrix_file;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

required options:

  -p  <integer> project id
  -t  <string>  type (default $type)
  -l  <string>  level (default $level)
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
my $data_dir = abs_path($script_dir."/../../storage/ProcessedResults");
#my $annotation_file = abs_path($script_dir."/../ref/RSEM/gencode.v19.annotation.txt");
my $annotation_file = abs_path($script_dir."/../ref/RSEM/gencode.v36lift37.annotation.txt");

if (!$project_id) {
	die "Some parameters are missing\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();

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
	my $sql_prj = "select name, version from projects where id=$project_id";
	my $sql_samples = "select distinct s.sample_id, s.sample_name, s.sample_alias, c.patient_id, c.case_id, c.path, s.library_type, s.tissue_type from project_samples p,samples s, sample_cases sc, cases c where sc.sample_id = s.sample_id and s.exp_type='RNAseq' and p.project_id=$project_id and p.sample_id=s.sample_id and sc.case_id=c.case_id and sc.patient_id=c.patient_id and not exists(select * from sample_details d where s.sample_id=d.sample_id and attr_name='status' and attr_value='Failed') order by s.sample_id";
	my %data = ();
	my %targets = ();
	my %lib_types = ();
	my %tissue_types = ();
	my %coding_symbols = ();
	my %sample_names = ();	
	my $start = time;
	my $sth_prj = $dbh->prepare($sql_prj);
	my $sth_samples = $dbh->prepare($sql_samples);
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
	my $exp_list_file = "$out_dir/exp_list-$type-$level.tsv";
	open(EXP_LIST_FILE, ">$exp_list_file") or die "Cannot write file $exp_list_file";
	
	$sth_samples->execute();
	my $total_samples = 0;	
	while (my ($sample_id, $sample_name, $sample_alias, $patient_id, $case_id, $path, $lib_type, $tissue_type) = $sth_samples->fetchrow_array) {
		#save coding symbol to hash
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
				system("cut -f1,5 $expfile > $count_file");
				system("cut -f1,6 $expfile > $tpm_file");		
				$total_samples++;					
			}
		} else {
			print("RSEM file not found: $path. Sample: $sample_id\n");			
		}		
	} # end of while

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

	my $cmd = "$r_path/Rscript $script_dir/tmmNormalize.r $exp_list_file $annotation_file $out_dir";
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
	
	if ($matrix_file) {
		system("cp $matrix_file $out_dir/expression.tmm-rpkm.tsv");
	}

	foreach my $norm_type (@norm_types) {
		print "inserting $norm_type\n";
		if (!$dry_run) {			
			&insertProjectValues("$out_dir/expression.$norm_type.tsv", $norm_type);
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
	
	$duration = time - $start;
	print "time(runStat): $duration s\n";
	$dbh->do("update projects set status=2 where id=$project_id");
	$dbh->commit();	
	$dbh->disconnect();
	system("mkdir -p $out_dir/cor");
	system("mkdir -p $out_dir/survival");
	system("chmod g+w $out_dir/cor");
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
				$row_count++;
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
	open(FILE, "$exp_file") or die "Cannot open file $exp_file";
	my $num_anno_fields = 9;
	my $header = <FILE>;
	chomp $header;
	my @sample_ids = split(/\t/, $header);
	splice(@sample_ids, 0, $num_anno_fields);
	my @sample_names = ();
	my @sample_alias_list = ();
	#splice(@sorted_samples, 0, 1);
	$sth_delete_project_expression->execute($project_id, $type, $level, $norm_type);
	foreach my $sample_id (@sample_ids) {
		next if ($sample_id eq "");
		$sth_insert_project_expression->execute($project_id, $sample_id, $type, $level, $norm_type);
	}
	#my $sample_name_list = join("\t", @sorted_samples);
	my $sample_name_list = join("\t", @sample_alias_list);
	$sth_delete_project_value->execute($project_id, $type, $level, $norm_type);	
	$sth_insert_project_value->execute($project_id, "_list", "_list", "_list", $type, $level, $norm_type, join(",", @sample_ids));
	#my $sample_list = join("\t", @sorted_samples);
	my $sample_alias_list_str = join("\t", @sample_alias_list);
	my $rec = 0;

	while(<FILE>) {
		chomp;
		my @fields = split(/\t/);
		if ($#fields > 1) {
			next if ($fields[5] ne "protein_coding");
			my $target = $fields[0];
			my $gene = $fields[4];
			my $symbol = $fields[7];
			splice(@fields, 0, $num_anno_fields);
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
			$rec++;
			#if ($rec % 2000 == 0) {
			#	$dbh->commit();
			#}			
			$sth_insert_project_value->execute($project_id, $target, $gene, $symbol, $type, $level, $norm_type, $value_list); 
		}
	}
	close(FILE);	
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

	#for NF pipeline
	if ($type eq "ensembl")	{		
		my $sample_file = "$path/$sample_name/RSEM_ENS/$sample_name.genes.results";	
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
