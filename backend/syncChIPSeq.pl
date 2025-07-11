#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Try::Tiny;
use MIME::Lite; 
use JSON;
use Data::Dumper;
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");


local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $input_dir;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -i  <string>  Input folder
  
__EOUSAGE__



GetOptions (
  'i=s' => \$input_dir
);

if (!$input_dir) {
    die "input folder are missing\n$usage";
}

my $script_dir = dirname(__FILE__);

my $dbh = getDBI();
my $sid = getDBSID();
my $db_type = getDBType();

my $sample_id = basename($input_dir);
my $flagstat = "$input_dir/${sample_id}.flagstat.txt";
if ( ! -e $flagstat) {
	die("flagstat file not found!\n");
}
my $sth_smp = $dbh->prepare("select patient_id from samples where sample_id='$sample_id'");
$sth_smp->execute();
my $patient_id;
if (my ($pid) = $sth_smp->fetchrow_array) {
	$patient_id = $pid;	
}
$sth_smp->finish;

my $sth_insert = $dbh->prepare("insert into chipseq values(?,?,?,?,?,?,?,?,?)");


open(FLAGSTAT_FILE, "$flagstat") or die "Cannot open file $flagstat";
my $mapped = 0;
my $dup = 0;
my $paired = 0;
while (<FLAGSTAT_FILE>) {
	chomp;
	if (/in total/) {
		($mapped) = $_ =~ /(\d+)\s/;
	}
	if (/duplicates/) {
		($dup) = $_ =~ /(\d+)\s/;
	}
	if (/properly paired/) {
		($paired) = $_ =~ /(\d+)\s/;
	}
}
my $dup_rate = $dup/$mapped;
close(FLAGSTAT_FILE);
my $has_spike_in = "N";
my $spike_in_reads = 0;
my $spike_in_file = "$input_dir/SpikeIn/spike_map_summary";
if ( -e $spike_in_file ) {
	open(SPIKEIN_FILE, "$spike_in_file") or die "Cannot open file $spike_in_file";
	<SPIKEIN_FILE>;
	my $line = <SPIKEIN_FILE>;
	chomp $line;
	my @tokens = split(/\t/, $line);
	$spike_in_reads = $tokens[1];
	$has_spike_in = "Y";
}
close(SPIKEIN_FILE);

my @peak_files = grep { -f } glob "$input_dir/MACS_Out_*/*nobl.bed";
my @peak_counts = ();
my $super_enchancer = "N"; 

foreach my $peak_file(@peak_files) {
	#print("$peak_file\n");
	my $count = readpipe("wc -l $peak_file | cut -f1 -d' '");
	chomp $count;
	(my $cutoff) = $peak_file =~ /MACS_Out_(.*?)\//;
	push @peak_counts, "$cutoff:$count";
}

my @rose_files = grep { -f } glob "$input_dir/MACS_Out_q_1e-02/ROSE_out_*/*_peaks_SuperStitched.table.txt";
if ($#rose_files >= 0) {
		$super_enchancer = "Y";
}

my $total_file = "$input_dir/../total_reads.txt";
my $total_reads;
if ( -e $total_file ) {
	open(TOTAL_FILE, "$total_file") or die "Cannot open file $total_file";
	while (<TOTAL_FILE>) {
		chomp;
		my @fs = split(/\t/);
		if ($#fs == 1) {
				if ($fs[0] eq $sample_id) {
					$total_reads = $fs[1];
				}
		}
	}
}
if ($paired > 0) {
	if (!$total_reads) {
			$total_reads = $total_reads*2;
	}
	$paired = "Y";
} else {
	$paired = "N";
}
close(TOTAL_FILE);
$dbh->do("delete chipseq where sample_id='$sample_id'");
$sth_insert->execute($sample_id, $total_reads, $mapped, $dup, $paired, $has_spike_in, $spike_in_reads, join(",", @peak_counts), $super_enchancer);
print ("$patient_id $sample_id $paired $total_reads $mapped $dup $dup_rate $has_spike_in $spike_in_reads ".join(",", @peak_counts)." $super_enchancer\n");
$dbh->commit();


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



