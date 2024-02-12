#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use LWP::Simple;
use Scalar::Util qw(looks_like_number);
use Try::Tiny;
use MIME::Lite; 
use File::Temp qw/ tempfile tempdir /;
use POSIX;
use Cwd 'abs_path';

local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $dir;
my $target_patient;
my $target_case;
my $url = "https://fr-s-bsg-onc-d.ncifcrf.gov/clinomics_dev/public";
my $db_name = "development";



my $script_dir = abs_path(dirname(__FILE__));
my $app_path = $script_dir."/../..";
my $storage_path = $script_dir."/../../storage/ProcessedResults/";
print $storage_path;

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1,    
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);


my $get_patients = $dbh->prepare("select patient_id,diagnosis,is_cellline from Patients");
my $get_cases=$dbh->prepare("select distinct c.case_id, c.case_name, c.patient_id, 
				(select count(*) from var_samples p where p.patient_id=c.patient_id and p.case_id=c.case_id and type='germline') as germline,
				(select count(*) from var_samples p where p.patient_id=c.patient_id and p.case_id=c.case_id and type='somatic') as somatic,
				(select count(*) from var_samples p where p.patient_id=c.patient_id and p.case_id=c.case_id and type='rnaseq') as rnaseq,
				(select count(*) from var_samples p where p.patient_id=c.patient_id and p.case_id=c.case_id and type='variants') as variants,
				(select count(*) from var_fusion p where p.patient_id=c.patient_id and p.case_id=c.case_id) as fusion,
				c.finished_at as pipeline_finish_time, 
				c.updated_at as upload_time,
				status 
				from cases c where c.patient_id = ? and case_name is not null");
my $get_samples=$dbh->prepare("select s1.* from samples s1, processed_sample_cases s2 where s1.patient_id=s1.patient_id and s2.patient_id= ? and s2.case_id= ? and s1.sample_id=s2.sample_id");
my $get_path=$dbh->prepare("select path from cases where patient_id=? and case_id=? ");

$get_patients->execute();
my @row = $get_patients->fetchrow_array;
my $count=0;
my $folder ="TPM_UCSC";
my $level_str="gene";
my $file_type=".txt";
my $suffix = ".".$level_str.".TPM".$file_type;
my $filename = './report.txt';
open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
my $lines="patient_id\tdiagnosis\tcase_id\tis_cell_line\ttissue\tsample_id\tlibrary\tfile_path\n";

while (my @row_array = $get_patients->fetchrow_array) {
	my $patient_id=$row_array[0];
	my $diagnosis=$row_array[1];
	my $is_cell_line=$row_array[2];
	if(!$is_cell_line){
		$is_cell_line="null";
	}
	$get_cases->execute($patient_id);
	while (my @row_array_cases = $get_cases->fetchrow_array) {
    	#print $patient_id."\t".$diagnosis. "\n";
    	my $case_id=$row_array_cases[0];
    	$get_samples->execute($patient_id,$case_id);
    	$get_path->execute($patient_id,$case_id);
    	my @row_path = $get_path->fetchrow_array;
		my $path =$row_path[0];
    	while (my @row_array_samples = $get_samples->fetchrow_array) {
    		my $sample_id=$row_array_samples[0];
    		my $sample_name=$row_array_samples[1];
    		my $library=$row_array_samples[8];
    		my $tissue=$row_array_samples[9];
    		if(!$library){
    			$library="null";
    		}
    		my $file_path=getFilePath($patient_id,$case_id,$path, $sample_id, $sample_name);
    		#if ($file_path == "") {
			#	$suffix = "_fpkm.Gene".$file_type;
			#	my @file_path=getFilePath($patient_id,$case_id,$path, $sample_id, $sample_name);
			#	my $suffix = ".".$level_str.".TPM".$file_type;
				#print $file_path[0]."\n";
			#}
			if ($file_path ne "") {
				$file_path="/ProcessedResults/".$file_path;
				$lines.=$patient_id."\t".$diagnosis."\t".$case_id."\t".$is_cell_line."\t".$tissue."\t".$sample_id."\t".$library."\t".$file_path."\n";
				print $patient_id."\t".$diagnosis."\t".$case_id."\t".$is_cell_line."\t".$tissue."\t".$sample_id."\t".$library."\t".$file_path."\n";

			}


    	}

	}
    
   # print $count."\n";

}
print $fh $lines;

sub getFilePath{
	 my ($patient_id,$case_id,$path, $sample_id, $sample_name) = @_;
		my $sample_file = "$path/$patient_id/$case_id/$sample_id/$folder/$sample_id$suffix";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;
		}

		$sample_file = "$path/$patient_id/$case_id/$sample_id/$folder/$sample_id/$sample_id$suffix";

		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;

		}
		$sample_file = "$path/$patient_id/$case_id/$sample_name/$folder/$sample_name$suffix";
	#	print $storage_path.$sample_file."\n";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_name);
			return $sample_file;
	
		}
		$sample_file = "$path/$patient_id/$case_id/$sample_name/$folder/$sample_name/$sample_name$suffix";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_name);
			return $sample_file;	
		}
		$sample_file = "$path/$patient_id/$case_id/Sample_$sample_id/$folder/Sample_$sample_id$suffix";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, "Sample_$sample_id");
			return $sample_file;
		}
		$sample_file = "$path/$patient_id/$case_id/Sample_$sample_id/$folder/Sample_$sample_id/Sample_$sample_id$suffix";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, "Sample_$sample_id");
			return $sample_file;
		}
		$sample_file = "$path/$patient_id/$case_id/Sample_$sample_name/$folder/Sample_$sample_name$suffix";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, "Sample_$sample_name");
			return $sample_file;
		}
		$sample_file = "$path/$patient_id/$case_id/Sample_$sample_name/$folder/Sample_$sample_name/Sample_$sample_name$suffix";
		if (-e $storage_path.$sample_file){ 
			my @array=($sample_file, "Sample_$sample_name");
			return $sample_file;	

		}
		my @array=("","");
		return "";
	}