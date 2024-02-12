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
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);
local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $dir;
my $target_patient;
my $target_case;
my $db_name = "production";
my $patient_data ="";
my $project_name ="";
my $project_description="";

my $dbh = getDBI();
#$dbh->trace(4);

my $get_diagnosis=$dbh->prepare("select * from diagnosis");
my $get_patients=$dbh->prepare("select diagnosis,patient_id from patients");

my %All_diagnosis;

$get_diagnosis->execute();
my $filename = './Diagnosis_report.txt';
my $filename2 = './Diagnosis_reportNoTCGA.txt';

open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
open(my $fh2, '>', $filename2) or die "Could not open file '$filename' $!";

while (my @row = $get_diagnosis->fetchrow_array) {
	my $primary=$row[1];
	my $secondary=$row[3];
	my $tertiary=$row[5];
	my $quaternary=$row[7];
	my $quinternary=$row[9];
	if(defined $tertiary){
		$All_diagnosis{$tertiary}="";
	}
	$All_diagnosis{$primary}="";
	$All_diagnosis{$secondary}="";
	if(defined $quaternary){
		$All_diagnosis{$quaternary}="";
	}
	if(defined $quinternary){
		$All_diagnosis{$quinternary}="";
	}
}		
	my $keys = keys(%All_diagnosis) ;
	print "keys = $keys\n" ;
$get_patients->execute();
my $lines="";
my $lines2="";

while (my @patient_row = $get_patients->fetchrow_array) {
	my $patient_id=$patient_row[1];
	my $diagnosis= $patient_row[0];
	if($diagnosis ne "xxxx"){
		if (exists($All_diagnosis{$diagnosis})!=1){
				#print $patient_id."\t".$diagnosis."\n";
				$lines=$lines.$patient_id."\t".$diagnosis."\n";
			if (index($patient_id, "TCGA") == -1){
				print $patient_id."\t".$diagnosis."\n";
				$lines2=$lines2.$patient_id."\t".$diagnosis."\n";
 
			}

		}
	}

}
print $fh $lines;
print $fh2 $lines2;


