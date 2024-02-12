#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use LWP::Simple qw(get);

my $script_dir = dirname(__FILE__);

my $url = "https://fr-s-bsg-onc-d.ncifcrf.gov/clinomics_dev/public";
my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd, $port) = split(/\t/, $db_config[0]);

my $dbh = DBI->connect( "dbi:Oracle:host=$host;port=$port;sid=$sid", $username, $passwd, {
    AutoCommit => 0,
    RaiseError => 1, 
    LongReadLen  => 120000
}) || die( $DBI::errstr . "\n" );

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
my $sth_trans = $dbh->prepare("select trans,aa_seq from transcripts");
#my $sth_trans = $dbh->prepare("select trans,aa_seq from transcripts where trans in ('NM_017655','NM_178191','NM_004195')");
#my $sth_new_trans = $dbh->prepare("insert into transcripts values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
$sth_trans->execute();
my $count = 0;
my $app_path = $script_dir."/../..";

my @rows = ();
print STDERR "Retriving data from DB...\n";
my $i=0;
while (my @row = $sth_trans->fetchrow_array) {
    push @rows, \@row;
    $i++;
}
$sth_trans->finish;
$dbh->disconnect();
print STDERR "Calculating protein domain...\n";
foreach my $row (@rows) {
    my @array = @$row;
    #my ($chr, $start_pos, $end_pos, $coding_start, $coding_end, $data_type, $strand, $gene, $symbol, $key, $seq, $aa_seq, $canonical) = @array;
    my ($key, $prot) = @array;
	#my ($offset, $prot) = &dna2protein($seq);
    my ($fh, $filename) = tempfile();
    my $domain = "";
    if ($prot) {
        print $fh ">$key\n$prot";
        my $cmd = "php $script_dir/getPfamDomain.php app_path=$app_path in_file=$filename";
        my @lines = readpipe($cmd);
        close($fh);
        system("rm -f $filename");        
        if (@lines) {
            $domain = $lines[0];
        }
    }
	#my $curl = "$url/predictPfamDomain/$key/$prot";
	#my $domain = get $curl;
    #if (!$domain) {
    #    $domain = "[]";
    #}
    #if (!$canonical) {
    #    $canonical = "";
    #}
    print join("\t", $key, $domain)."\n";
	#$sth_new_trans->execute($chr, $start_pos, $end_pos, $coding_start, $coding_end, $data_type, $strand, $gene, $symbol, $key, $seq, $prot, $domain, $offset);
	#$count++;
	#if ($count == 5000) {
    #	$dbh->commit();  
	#	$count = 0;
	#}
	
}

#$dbh->commit();


sub dna2protein {
	my ($dna) = @_;	
	my @offsets = (0);
	if (substr($dna, 0, 3) ne "ATG") {
		push @offsets, 1;
		push @offsets, 2;		
	}
	
	my $protein = "";
	my $max_orf = 0;
	my $max_offset = 0;
	foreach my $offset (@offsets) {
		my $prot = "";
		for(my $i=$offset;$i<(length($dna)-2);$i+=3) {
			my $codon = substr($dna,$i,3);
			$prot .= &codon2aa($codon);
		}
		my $orf_length = index($prot, '*');
		if ($orf_length == -1) {
			$orf_length = length($prot);
		}
		if ($orf_length > $max_orf) {
			$protein = $prot;
			$max_orf = $orf_length;
			$max_offset = $offset;
		}
	}
	return ($max_offset, $protein);
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
