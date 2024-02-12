#/usr/bin/perl
use strict;
use Data::Dumper;
my $myhostname=`hostname`;chomp $myhostname;
$ENV{'ORACLE_HOME'}='/opt/nasapps/production/oracle/product/11.2.0/client';
my $script_home_dev="/mnt/webrepo/$myhostname/htdocs/clinomics_dev/app/scripts/backend";
my $script_home_production="/mnt/webrepo/$myhostname/htdocs/clinomics/app/scripts/backend";
my $data_home="/mnt/webrepo/$myhostname/htdocs/clinomics/app/storage/data";
my $linking_dir='/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults';
my $processed_data='processed_DATA';
my $target_file=$ARGV[0];
my $target_project=$ARGV[1];
my $target_db=$ARGV[2];
my $target_mf=$ARGV[3];
if   ($#ARGV <=0){
	print "Usage: $0 {target file} {target project} $#ARGV";
	exit ;
}
$target_db||='production';
$target_mf||='';

#Gets all of the patients required to be processed
open (INPUT,"<$target_file") or die "cannot open file $target_file\n";
my %required;
while (my $line=<INPUT>){
	chomp $line;
	my $patient= my $case= my $empty='';
	if ($line=~/successful.txt/){
		($patient,$case,$empty)=split("/",$line);
	}else{
		$patient=$line;
	}
	$required{$patient}=$case;
}
my $clinomics_master_file="$data_home/ClinOmics_Sequencing_Master_File_db.txt";
my $khanlab_master_file="$data_home/Sequencing_Tracking_Master_db.txt";
my $other_master_file="$data_home/SequencingMasterFile_OutsidePatients_db.txt";
my $tcga_master_file="$data_home/TCGAMaster.txt";
my $gtex_master_file="$data_home/GTEXMaster.txt";
my $public_master_file="$data_home/Sequencing_Tracking_Master_Public_db.txt";
my $khanlab_modified = my $clinomics_modified = my $other_modified = my $tcga_modified = my $gtex_modified = my $public_modified = 0;
my $todaysdate=`date "+%Y%m%d"`;chomp $todaysdate;
my @files ;
if (defined ($target_mf) && $target_mf=~/\w+/){
	@files=split(",",$target_mf);
}else{
	@files= ($khanlab_master_file,$other_master_file,$tcga_master_file,$gtex_master_file,$public_master_file);
}
my %found=();my $header=0;my @processMFList=();my %headers;
my $khanlab_modified=0;my $sfx = ".public$todaysdate.txt";

##Reads through master file and processes all patients in the master file and outputs to a different MASTER FILE
foreach my $mf (@files){
	$header=0;
	open (FILE,"<$mf") or die "Cannot open Master file $mf\n";
	open (MFOUT,">$mf$sfx") or die "cannot open for writing $mf.public$todaysdate.txt";
	while (my $line=<FILE>){
		chomp $line;
		if ($header){
			my @info = split("\t",$line);
			my $patient = $info[$headers{'patient_id'}];
			$patient=~s/\s//g;
			my $project = $info[$headers{'project'}];
			
			if (exists $required{$patient} && $project=~/\b$target_project\b/){
				if (exists $found{$patient} && $found{$patient} ne $mf){
					print "Found patient $patient in $mf and $found{$patient}\n";exit;
				}else{
					$found{$patient}=$mf;
					if ($mf=~/Sequencing_Tracking_Master/){
						$khanlab_modified=1 ;
					}elsif($mf=~/clinomics/i){
						$clinomics_modified=1;
					}elsif ($mf=~/Outside/){
						$other_modified = 1 ;
					}elsif ($mf=~/TCGA/){
						$tcga_modified = 1;
					}elsif ($mf=~/GTEX/){
						$gtex_modified = 1;
					}elsif ($mf=~/Public/){ 
						$public_modified = 1;
					}

				}
				if ($project=~/\b$target_project\b/i && $project ne $target_project){
					$info[$headers{'project'}]=$target_project;
				}
				$info[$headers{'project'}]=$target_project;
				print MFOUT join ("\t",@info) . "\n";
			}
			
		}else{#read headers and get the patient_id and the project;
			my @headers=split("\t",$line);my $count=0;
			%headers = map {lc($_) => $count++} @headers;
			if ( (exists $headers{'patient_id'}|| exists($headers{'custom id'})) && exists ($headers{'project'})){
				if (!exists $headers{'patient_id'}){
					$headers{'patient_id'}=$headers{'custom id'};
				}
			}else{
				print Dumper (\%headers);
				print "Checking headers: $mf failed\n";exit;
			}
			$header=1;
			print MFOUT "$line";
		}
	}
	close MFOUT;close FILE;
	print "Done with $mf\n";

}

#now check which patients are missing from the master files and link any new ones to the public directory
chdir("/is2/projects/CCR-JK-oncogenomics/static/ProcessedResults/public_data/$processed_data");
foreach my $patient (keys %required){
	if (!exists $found{$patient}){
		print "not found $patient\n";
	}elsif (-e "$linking_dir/$processed_data/$patient"  ){
		if (!-e "$linking_dir/public_data/$processed_data"){
			system ("mkdir $linking_dir/public_data/$processed_data\n");
		}
		if (!-l "$linking_dir/public_data/$processed_data/$patient"){
			system ("ln -s ../../$processed_data/$patient .\n");
		}else{
			print "already exists\n";
		}
	}else{
		print "$linking_dir/$processed_data/$patient not exists...please specify new (processed_DATA|clinomics|guha) directory (current=$processed_data)";
	}
}

if ($khanlab_modified == "1" ){
	print "Testing  master files..." .`date`;
	print "$script_home_dev/VerifyMasterFile.pl -i $khanlab_master_file$sfx\n";
	eval{
		system ("$script_home_dev/VerifyMasterFile.pl -i $khanlab_master_file$sfx\n");
	};
	if ($@){
		print "die couldn't not verify master\n$script_home_production/VerifyMasterFile.pl -i $khanlab_master_file$sfx\n";
		exit;
	}
}
print '------------------' . `date`;
if($target_db=~/(prod|all)/){
	
	print "Uploading production database ($target_db)...\n";
	my $cmd =  "$script_home_production/syncMaster.pl -u -n production -i $clinomics_master_file$sfx,$khanlab_master_file$sfx,$other_master_file$sfx,$tcga_master_file$sfx,$gtex_master_file$sfx,$public_master_file$sfx -m $clinomics_modified,$khanlab_modified,$other_modified,$tcga_modified,$gtex_modified,$public_modified";
	system ("$cmd");
}
if ($target_db=~/(dev|all)/){
	print "Uploading development database ($target_db)...\n";
	my $cmd= "$script_home_dev/syncMaster.pl -u -i $clinomics_master_file$sfx,$khanlab_master_file$sfx,$other_master_file$sfx,$tcga_master_file$sfx,$gtex_master_file$sfx,$public_master_file$sfx -m $clinomics_modified,$khanlab_modified,$other_modified,$tcga_modified,$gtex_modified,$public_modified";
	print "$cmd\n";
	system ("$cmd\n");
	
}
print "done!";


# #select s1.sample_id, s1.patient_id, s1.biomaterial_id, s1.source_biomaterial_id, s1.exp_type, s1.tissue_cat, s1.tissue_type, s2.sample_id as normal_sample from samples s1, samples s2 where s1.patient_id=s2.patient_id and s1.tissue_cat='tumor' and s2.tissue_cat in ('normal','blood') and s1.exp_type=s2.exp_type and s1.platform='Illumina' and s2.platform='Illumina' and s1.relation='self' and s2.relation='self' order by s1.sample_id
# #select s1.sample_id, s1.patient_id, s1.biomaterial_id, s1.source_biomaterial_id, s1.exp_type, s1.tissue_cat, s1.tissue_type, s2.sample_id as rna_sample from samples s1, samples s2 where s1.patient_id=s2.patient_id and s1.tissue_cat='tumor' and s1.exp_type <> 'RNAseq' and s2.exp_type='RNAseq' and s1.source_biomaterial_id=s2.source_biomaterial_id and s1.platform='Illumina' and s2.platform='Illumina' and s1.relation='self' and s2.relation='self' order by s1.sample_id
