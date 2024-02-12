#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;


my $in_file;
my $data_type = "refseq";
my $blastdb = "/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.sandbox1/app/storage/data/blastdb/hg19";

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -i  <string>  Input sorted BED file  
  -t  <string>  Data type: (refseq, ensembl), default: $data_type
  -d  <string>  Blast DB, default: $blastdb
  
__EOUSAGE__



GetOptions (
  'i=s' => \$in_file,
  't=s' => \$data_type
);

if (!$in_file) {
    die "Some parameters are missing\n$usage";
}

my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1, 
    LongReadLen  => 66000
}) || die( $DBI::errstr . "\n" );
#$dbh->trace(4);


my $sql_exon = "insert into exon_coordinate values(?,?,?,?,?,?,?,?,?)";
my $sql_trans = "insert into trans_coordinate values(?,?,?,?,?,?,?,?,?,?,?,?)";
my $sth_exon = $dbh->prepare($sql_exon);
my $sth_trans = $dbh->prepare($sql_trans);
my $table_name = ($data_type eq "refseq")? "exon_coord" : "exon_coord_ensembl";
my $sth_coord = $dbh->prepare("select seq from $table_name where chr=? and start_pos=? and end_pos=?");
my $sth_trans_exists = $dbh->prepare("select count(*) from trans_coordinate where trans=?");
my %coord = ();
my %exist_trans = ();
my %trans_id = ();
my %trans_coord = ();
#$dbh->do("delete exon_coordinate where data_type = '$data_type'");
#$dbh->do("delete trans_coordinate where data_type = '$data_type'");
open(IN_FILE, $in_file) or die "Cannot open file $in_file";
my $current_chr = "";

my(%genetic_code) = (    
    'TCA' => 'S',    # Serine
    'TCC' => 'S',    # Serine
    'TCG' => 'S',    # Serine
    'TCT' => 'S',    # Serine
    'TTC' => 'F',    # Phenylalanine
    'TTT' => 'F',    # Phenylalanine
    'TTA' => 'L',    # Leucine
    'TTG' => 'L',    # Leucine
    'TAC' => 'Y',    # Tyrosine
    'TAT' => 'Y',    # Tyrosine
    'TAA' => '*',    # Stop
    'TAG' => '*',    # Stop
    'TGC' => 'C',    # Cysteine
    'TGT' => 'C',    # Cysteine
    'TGA' => '*',    # Stop
    'TGG' => 'W',    # Tryptophan
    'CTA' => 'L',    # Leucine
    'CTC' => 'L',    # Leucine
    'CTG' => 'L',    # Leucine
    'CTT' => 'L',    # Leucine
    'CCA' => 'P',    # Proline
    'CCC' => 'P',    # Proline
    'CCG' => 'P',    # Proline
    'CCT' => 'P',    # Proline
    'CAC' => 'H',    # Histidine
    'CAT' => 'H',    # Histidine
    'CAA' => 'Q',    # Glutamine
    'CAG' => 'Q',    # Glutamine
    'CGA' => 'R',    # Arginine
    'CGC' => 'R',    # Arginine
    'CGG' => 'R',    # Arginine
    'CGT' => 'R',    # Arginine
    'ATA' => 'I',    # Isoleucine
    'ATC' => 'I',    # Isoleucine
    'ATT' => 'I',    # Isoleucine
    'ATG' => 'M',    # Methionine
    'ACA' => 'T',    # Threonine
    'ACC' => 'T',    # Threonine
    'ACG' => 'T',    # Threonine
    'ACT' => 'T',    # Threonine
    'AAC' => 'N',    # Asparagine
    'AAT' => 'N',    # Asparagine
    'AAA' => 'K',    # Lysine
    'AAG' => 'K',    # Lysine
    'AGC' => 'S',    # Serine
    'AGT' => 'S',    # Serine
    'AGA' => 'R',    # Arginine
    'AGG' => 'R',    # Arginine
    'GTA' => 'V',    # Valine
    'GTC' => 'V',    # Valine
    'GTG' => 'V',    # Valine
    'GTT' => 'V',    # Valine
    'GCA' => 'A',    # Alanine
    'GCC' => 'A',    # Alanine
    'GCG' => 'A',    # Alanine
    'GCT' => 'A',    # Alanine
    'GAC' => 'D',    # Aspartic Acid
    'GAT' => 'D',    # Aspartic Acid
    'GAA' => 'E',    # Glutamic Acid
    'GAG' => 'E',    # Glutamic Acid
    'GGA' => 'G',    # Glycine
    'GGC' => 'G',    # Glycine
    'GGG' => 'G',    # Glycine
    'GGT' => 'G',    # Glycine
    );

my $count = 0;
while(<IN_FILE>) {
	chomp;
	my ($chr, $start_pos, $end_pos, $symbol, $no_use, $trans_info) = split(/\t/);
	if ($trans_info) {		
		my ($trans, $type, $strand)=$trans_info=~/(.*)_(.*)_(.*)/;
		#print "process trans: $trans";
		if (!$exist_trans{$trans}) {
			if (&checkTransExists($trans)) {
				#print "...found!";
				$exist_trans{$trans} = '';
				next;
			}
		}
		#print "...not found!";
		my $one_base_start = $start_pos + 1;
		$strand = ($strand eq "f")? "+" : "-";
		$chr = "chr".$chr;
		if ($current_chr ne $chr) {
			%coord = ();
			if ($current_chr ne "") {
				print "saving chromosome $current_chr...";
				&saveTranscript();
				%trans_coord = ();
				%trans_id = ();
				$count = 0;	
				print "done\n";
			}
			$current_chr = $chr;		
		}
		# get coord information 1.from hash 2. from db 3. from blast
		my $key = "$chr:$one_base_start"."-".$end_pos;
		#my $seq = $coord{$key};		
		#if (!$seq) {
		#	$sth_coord->execute($chr, $one_base_start, $end_pos);
		#	if (my @row = $sth_coord->fetchrow_array) {
		#		$seq = $row[0];
		#	}			
		#	else {
		#		$cmd = "$script_dir/getSequence.sh $blastdb $chr $one_base_start $end_pos";
		#		$seq = readpipe($cmd);
		#		chomp $seq;
		#	}
		#	$sth_coord->finish;
		#}
		my $seq = '';
		$coord{$key} = $seq;
		#$sth_exon->execute($chr, $start_pos, $end_pos, $data_type, $symbol, $symbol, $trans, $type, $seq);
		my $current_trans = $trans;
		my $coding_seq = "";
		if (exists $trans_id{$trans}) {
			$current_trans = $trans_id{$trans};
			# if transcript exists and found new transcript then change transcript ID
			if ((($strand eq "+" && $type eq "utr5") || ($strand eq "-" && $type eq "utr3")) && exists $trans_coord{$current_trans}{"coding_seq"}) {
				if ($current_trans =~ /.*_(\d)$/) {
					my $idx = $1;
					$idx++;
					$current_trans = $trans."_".$idx;
				}
				else{
					$current_trans = "$trans"."_2";
				}
			}
		}
		$trans_id{$trans} = $current_trans;
		#$sth_exon->execute($chr, $start_pos, $end_pos, $data_type, $symbol, $symbol, $current_trans, $type, $seq);
		if (exists $trans_coord{$current_trans}) {
			$trans_coord{$current_trans}{"end_pos"} = $end_pos;			
			if ($type eq "cds") {
				# if first cds
				if (!exists $trans_coord{$current_trans}{"coding_start"}) {
					$trans_coord{$current_trans}{"coding_start"} = $start_pos;
				}
				$trans_coord{$current_trans}{"coding_end"} = $end_pos;
				$trans_coord{$current_trans}{"coding_seq"} .= $seq;
			}
		} else {
			$trans_coord{$current_trans}{"start_pos"} = $start_pos;
			$trans_coord{$current_trans}{"end_pos"} = $end_pos;
			$trans_coord{$current_trans}{"strand"} = $strand;
			$trans_coord{$current_trans}{"chr"} = $chr;
			$trans_coord{$current_trans}{"symbol"} = $symbol;
			if ($type eq "cds") {
				$trans_coord{$current_trans}{"coding_start"} = $start_pos;
				$trans_coord{$current_trans}{"coding_end"} = $end_pos;
				$trans_coord{$current_trans}{"coding_seq"} = $seq;				
			}
		}		
	}
	$count++;
	if ($count % 2000 == 0) {
		print "processed $count\n";
		#$dbh->commit();
	}
}
&saveTranscript(); 
$dbh->disconnect();

sub saveTranscript {
	foreach my $key (keys %trans_coord) {
		my $seq = $trans_coord{$key}{"coding_seq"};
		my $chr = $trans_coord{$key}{"chr"};
		my $start_pos = $trans_coord{$key}{"start_pos"};
		my $end_pos = $trans_coord{$key}{"end_pos"};
		my $coding_start = $trans_coord{$key}{"coding_start"};
		my $coding_end = $trans_coord{$key}{"coding_end"};
		my $strand = $trans_coord{$key}{"strand"};
		my $symbol = $trans_coord{$key}{"symbol"};
		my $aa_seq = "";
		if (!$seq) {
			$seq = "";
			$coding_start = $start_pos;
			$coding_end = $end_pos;			
		}
		else {
			if ($strand eq "-") {
				$seq =~ tr /atcgATCG/tagcTAGC/;
				$seq = reverse($seq);
			}
			$aa_seq = &dna2protein($seq);
		}
		#print "Inserting transcript: $key\n";
		$sth_trans->execute($chr, $start_pos, $end_pos, $coding_start, $coding_end, $data_type, $strand, $symbol, $symbol, $key, $seq, $aa_seq);
	}
	$dbh->commit();
}

sub dna2protein {
	my ($dna) = @_;
	my $protein = "";
	for(my $i=0;$i<(length($dna)-2);$i+=3) {
		my $codon = substr($dna,$i,3);
		$protein .= &codon2aa($codon);
	}
	return $protein;
}

sub codon2aa {
    my($codon) = @_;
	$codon = uc $codon;
	if(exists $genetic_code{$codon}) {
		return $genetic_code{$codon};
    }else{
		return "X";
    }
}

sub checkTransExists {
	my ($trans) = @_;
	$sth_trans_exists->execute($trans);
	my @row = $sth_trans_exists->fetchrow_array;
	my $exists = ($row[0] > 0);
	$sth_trans_exists->finish;
	return $exists;

}