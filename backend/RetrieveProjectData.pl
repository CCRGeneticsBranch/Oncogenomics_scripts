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
my $db_name = "production";



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


my $get_patients = $dbh->prepare("select * from project_samples where project_id=22112 and exp_type!='RNAseq' and tissue_cat='tumor'");
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
my $filename_sequenza = './CNV_samples_clinomics_sequenza.txt';
open(my $fh_sequenza, '>', $filename_sequenza) or die "Could not open file '$filename_sequenza' $!";

my $filename_kit = './CNV_samples_clinomics_kit.txt';
open(my $fh_kit, '>', $filename_kit) or die "Could not open file '$filename_kit' $!";

my $lines="patient_id\tcase_id\tsample_id\n";
my $lines_sequenza="";
my $lines_kit="";


while (my @row_array = $get_patients->fetchrow_array) {
	my $patient_id=$row_array[1];
	my $sample_id=$row_array[2];
	my $sample_name=$row_array[3];
	$get_cases->execute($patient_id);
	while (my @row_array_cases = $get_cases->fetchrow_array) {
    	#print $patient_id."\t".$diagnosis. "\n";
    	my $case_id=$row_array_cases[0];
#    	print "$patient_id\t$case_id\t$sample_id\n";
	   	$get_path->execute($patient_id,$case_id);
    	my @row_path = $get_path->fetchrow_array;
		my $path =$row_path[0];

    	my $file_path_sequenza=getFilePathSequenza($patient_id,$case_id,$path, $sample_id, $sample_name);
    	my $file_path_kit=getFilePathKit($patient_id,$case_id,$path, $sample_id, $sample_name);
    		#if ($file_path == "") {
			#	$suffix = "_fpkm.Gene".$file_type;
			#	my @file_path=getFilePath($patient_id,$case_id,$path, $sample_id, $sample_name);
			#	my $suffix = ".".$level_str.".TPM".$file_type;
				#print $file_path[0]."\n";
			#}
		if ($file_path_sequenza ne "") {
#			$file_path="/ProcessedResults/".$file_path;
			$lines_sequenza.="$patient_id\t$case_id\t$sample_id\n";
			#print "$patient_id\t$case_id\t$sample_id\n";
		}
		if ($file_path_kit ne "") {
#			$file_path="/ProcessedResults/".$file_path;
			$lines_kit.="$patient_id\t$case_id\t$sample_id\n";
			print "$patient_id\t$case_id\t$sample_id\n";
		}


    	}

	}
    
   # print $count."\n";


print $fh_sequenza $lines_sequenza;
print $fh_kit $lines_kit;


sub getFilePathSequenza{
	 my ($patient_id,$case_id,$path, $sample_id, $sample_name) = @_;
		my $sample_file = $path."/$patient_id/$case_id/$sample_name/sequenza/$sample_name/$sample_name"."_chromosome_view.pdf";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;
		}

		$sample_file = $path."/$patient_id/$case_id/$sample_id/sequenza/$sample_id/$sample_id"."_chromosome_view.pdf";

		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;

		}
		$sample_file = $path."/$patient_id/$case_id/Sample_$sample_id/sequenza/Sample_$sample_id/Sample_$sample_id"."_chromosome_view.pdf";
	#	print $storage_path.$sample_file."\n";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_name);
			return $sample_file;
	
		}
		my @array=("","");
		return "";
	}

sub getFilePathKit{
	 my ($patient_id,$case_id,$path, $sample_id, $sample_name) = @_;
		my $sample_file = $path."/$patient_id/$case_id/$sample_id/cnvkit/$sample_id".".pdf";
		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;
		}

		$sample_file = $path."/$patient_id/$case_id/Sample_$sample_id/cnvkit/Sample_$sample_id".".pdf";

		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;

		}

		$sample_file = $path."/$patient_id/$case_id/$sample_name/cnvkit/$sample_name".".pdf";

		if (-e $storage_path.$sample_file){
			my @array=($sample_file, $sample_id);
			return $sample_file;

		}
		
		my @array=("","");
		return "";
	}

