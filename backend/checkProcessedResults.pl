#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use MIME::Lite; 
use Cwd 'abs_path';
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $script_dir = dirname(__FILE__);

my $production_url = getConfig("URL_PRODUCTION");
my $project_file = abs_path($script_dir."/project_mapping.txt");
my %project_mapping = ();
open (PRJ, $project_file);
while(<PRJ>){
  my @fields = split(/\t/);
  $fields[2] =~ s/helix\.nih\.gov://;
  $project_mapping{$fields[0]} = $fields[2];
}

close(PRJ);
my $processed_data_dir = abs_path($script_dir."/../../../storage/ProcessedResults");
my $out_dir = abs_path("$processed_data_dir/../data_integrity_report");
my $bam_dir = abs_path($script_dir."/../../../storage/bams");

my $dbh = getDBI();

my %report = ();
# Steps:"
#"1: check successful.txt between Biowlf and Frederick servers
# 2: check if loaded no folders/successful.txt
# 3: check unused cases
# 4: check missing bams
# 5: check unprocessed cases
# 6: check missing RSEM cases
# generate summary table and html output

print("1: checking successful.txt between Biowlf and Frederick servers\n");
system("$script_dir/compareCaseDifference.sh all");

open(DIFF_CASES, "$out_dir/processed_list/diff_case_list.txt");
open(CASES_BIOWULF, ">$out_dir/cases_on_Biowulf_only.txt");
open(CASES_FREDERICK, ">$out_dir/cases_on_Frederick_only.txt");
print CASES_BIOWULF join("\t",("Patient_ID","Case_ID","Path","Biowulf_Path"))."\n";
print CASES_FREDERICK join("\t",("Patient_ID","Case_ID","Path","Biowulf_Path", "Case_Name"))."\n";
my $sth_cases = $dbh->prepare("select distinct patient_id,case_id,path,version,case_name from cases");
my $sth_processed_cases = $dbh->prepare("select distinct patient_id,case_id,path,version from processed_cases");
$sth_cases->execute();

my %cases = ();
my %processed_cases = ();
my %paths = ();
#get all cases
while (my ($patient_id,$case_id,$path,$version,$case_name) = $sth_cases->fetchrow_array) {
  $cases{join(",",($patient_id,$case_id,$path))} = $case_name;
  $paths{$path} = '';
}
$sth_cases->finish;

<DIFF_CASES>;
while(<DIFF_CASES>) {
  chomp;
  my @fields = split(/\t/);  
  if ($#fields == 5) {
    my ($path,$biowulf_path,$patient_id,$case_id,$biowulf,$frederick) = @fields;
    next if ($path eq "roper");
    $biowulf_path =~ s/helix\.nih\.gov://;
    if ($biowulf eq "Y") {
      push @{$report{"cases_on_Biowulf_only"}{$path}}, join("\t", ($patient_id,$case_id,$path,$biowulf_path));
      print CASES_BIOWULF join("\t", ($patient_id,$case_id,$path,$biowulf_path))."\n";
    } else {
      my $case_name = "NA";
      if (exists($cases{join(",", ($patient_id, $case_id, $path))})) {
        $case_name = $cases{join(",", ($patient_id, $case_id, $path))};
      }
      push @{$report{"cases_on_Frederick_only"}{$path}}, join("\t", ($patient_id,$case_id,$path,$biowulf_path,$case_name));
      print CASES_FREDERICK join("\t", ($patient_id,$case_id,$path,$biowulf_path,$case_name))."\n";
    }    
  }
}
close(DIFF_CASES);
close(CASES_BIOWULF);
close(CASES_FREDERICK);

print("2: checking if loaded no successful.txt\n");

open(NO_SUCCESSFUL_CASES, ">$out_dir/no_successful_cases.txt");
print NO_SUCCESSFUL_CASES join("\t",("Patient_ID","Case_ID","Path"))."\n";
$sth_processed_cases->execute();
while (my ($patient_id,$case_id,$path,$version) = $sth_processed_cases->fetchrow_array) {
  $processed_cases{join(",",($patient_id,$case_id,$path))} = '';  
  if ( ! -f "$processed_data_dir/$path/$patient_id/$case_id/successful.txt" ) {
    print NO_SUCCESSFUL_CASES join("\t",($patient_id,$case_id,$path))."\n";
    push @{$report{"no_successful_cases"}{$path}}, join("\t", ($patient_id,$case_id,$path,$version));

  }
}
close(NO_SUCCESSFUL_CASES);
$sth_processed_cases->finish;

#find unused folder
print("3: checking unused/unloaded cases\n");

open(UNUSED_CASES, ">$out_dir/unused_cases.txt");
open(UNLOADED_CASES, ">$out_dir/unloaded_cases.txt");

print UNUSED_CASES join("\t",("Patient_ID","Case_ID","Path"))."\n";
print UNLOADED_CASES join("\t",("Patient_ID","Case_ID","Path"))."\n";
for my $path (keys %paths) {
  my @patient_dirs = grep { -d } glob "$processed_data_dir/$path/*";
  foreach my $patient_dir (@patient_dirs) {
    my $patient_id = basename($patient_dir);
    my @case_dirs = grep { -d } glob $patient_dir."/*";
    foreach my $case_dir (@case_dirs) {
      my $case_id = basename($case_dir);
      if ( -f "$processed_data_dir/$path/$patient_id/$case_id/successful.txt") {
        if (!exists($cases{join(",",($patient_id,$case_id,$path))})) {
          print UNUSED_CASES join("\t",($patient_id,$case_id,$path))."\n";
          push @{$report{"unused_cases"}{$path}}, join("\t", ($patient_id,$case_id,$path));
        }
        if (!exists($processed_cases{join(",",($patient_id,$case_id,$path))})) {
          print UNLOADED_CASES join("\t",($patient_id,$case_id,$path))."\n";
          push @{$report{"unloaded_cases"}{$path}}, join("\t", ($patient_id,$case_id,$path));
        }
      }
    }
  }
}
close(UNUSED_CASES);
close(UNLOADED_CASES);

#find missing bams
print("4: checking missing bams\n");
my $sth_smps = $dbh->prepare("select distinct v.patient_id,v.case_id,c.case_name,v.sample_id,v.sample_name,c.path,c.exp_type from var_samples v,sample_cases c where 
v.patient_id=c.patient_id and v.case_id=c.case_id and v.sample_id=c.sample_id and c.exp_type in ('Exome','Panel','RNAseq') order by v.patient_id,v.case_id,v.sample_id");
$sth_smps->execute();

open(MISSING_BAMS, ">$out_dir/missing_bams.txt");
print MISSING_BAMS join("\t",("Patient_ID","Case_ID","Case_Name","Sample_ID","Sample_Name","Path","Source","Exp_Type","Case_Exist"))."\n";
#check if bam files exist
while (my ($patient_id,$case_id,$case_name,$sample_id,$sample_name,$path,$exp_type) = $sth_smps->fetchrow_array) {
  my $bam_squeeze_ext = ($exp_type eq "RNAseq")? "star.final.squeeze.bam" : "bwa.final.squeeze.bam";
  my $bam_ext = ($exp_type eq "RNAseq")? "star.final.bam" : "bwa.final.bam";
  my $bam_path = "$bam_dir/$path/$patient_id/$case_id/$sample_id/$sample_id.$bam_squeeze_ext";
  if ( ! -f $bam_path ) {
    $bam_path = "$bam_dir/$path/$patient_id/$case_id/Sample_$sample_id/Sample_$sample_id.$bam_squeeze_ext";
    if ( ! -f $bam_path ) {
      $bam_path = "$bam_dir/$path/$patient_id/$case_id/$sample_name/$sample_name.$bam_squeeze_ext";
      if ( ! -f $bam_path ) {
        $bam_path = "$bam_dir/$path/$patient_id/$case_id/$sample_name/$sample_name.bam";
        if ( ! -f $bam_path ) {
          my $case_exists = "N";
          $case_exists = "Y" if (-d "$processed_data_dir/$path/$patient_id/$case_id");
          my $src_dir = "NA";
          my $src_root = "NA";
          if ($project_mapping{$path}) {
            $src_root = $project_mapping{$path};
            $src_dir = $project_mapping{$path}."/$patient_id/$case_id/*/*$bam_ext";
            if ($path eq "compass_tso500") {
              $src_dir = $project_mapping{$path}."/$patient_id/$case_id/*/*.bam";
            }
          }
          print MISSING_BAMS join("\t", ($patient_id,$case_id,$case_name,$sample_id,$sample_name,$path,$src_dir,$exp_type,$case_exists))."\n";
          push @{$report{"missing_bams"}{$path}}, join("\t", ($path,$src_root,$patient_id,$case_id,$case_name,$sample_id,$sample_name));
        }
      }
    }
  }
}
$sth_smps->finish;
close(MISSING_BAMS);


print("5: checking unprocessed cases\n");
#6:
my $sth_smp_cases = $dbh->prepare("select distinct patient_id,case_name,exp_type from sample_cases where case_id is null order by patient_id");
$sth_smp_cases->execute();
open(UNPROCESSED_CASES, ">$out_dir/unprocessed_cases.txt");
print UNPROCESSED_CASES join("\t",("Patient_ID","Case_Name","Path"))."\n";
my %unprocessed_cases = ();
while (my ($patient_id,$case_name, $exp_type) = $sth_smp_cases->fetchrow_array) {
  if (! exists($unprocessed_cases{join("\t", ($patient_id,$case_name))})) {
    $unprocessed_cases{join("\t", ($patient_id,$case_name))} = '';
    my $path = "processed_DATA";
    if ($patient_id =~ /CP0/) {
      $path = ($exp_type eq "Panel")? "compass_tso500": "compass_exome";
    }
    print UNPROCESSED_CASES join("\t", ($patient_id,$case_name,$path))."\n";
    $report{"unprocessed_cases"}{"$path"}{join("\t", ($patient_id,$case_name))} = '';  
  }
}
close(UNPROCESSED_CASES);
$sth_smp_cases->finish;


print("6: checking missing RSEM\n");
my $sth_rna_smps = $dbh->prepare("select distinct patient_id,case_id,case_name,sample_id,sample_name,path from sample_cases where case_id is not null and exp_type='RNAseq' order by patient_id");
my $sth_smp_status = $dbh->prepare("select distinct sample_id,attr_value from sample_details where attr_name='status'");
$sth_smp_status->execute();
my %smp_status = ();
while (my ($sample_id,$status) = $sth_smp_status->fetchrow_array) {
  $smp_status{$sample_id} = $status;
}

$sth_smp_status->finish;
$sth_rna_smps->execute();

open(MISSING_RSEMS, ">$out_dir/missing_rsems.txt");
print MISSING_RSEMS join("\t",("Patient_ID","Case_ID","Case_Name","Sample_ID","Sample_Name","Path"))."\n";
#check if rsem files exist
while (my ($patient_id,$case_id,$case_name,$sample_id,$sample_name,$path) = $sth_rna_smps->fetchrow_array) {
  my $ext = "rsem_ENS.genes.results";
  my $rsem_path = "$processed_data_dir/$path/$patient_id/$case_id/$sample_id/RSEM_ENS/${sample_id}.$ext";
  if ( ! -f $rsem_path ) {
    $rsem_path = "$rsem_path/$path/$patient_id/$case_id/Sample_$sample_id/RSEM_ENS/Sample_$sample_id.$ext";
    if ( ! -f $rsem_path ) {
      $rsem_path = "$processed_data_dir/$path/$patient_id/$case_id/$sample_name/RSEM_ENS/$sample_name.$ext";
      if ( ! -f $rsem_path ) {
        $rsem_path = "$processed_data_dir/$path/$patient_id/$case_id/$sample_name/RSEM/$sample_name.$ext";
        if ( ! -f $rsem_path ) {
          if (exists $smp_status{$sample_id}) {
            next if ($smp_status{$sample_id} ne "Completed");
          }          
          print MISSING_RSEMS join("\t", ($patient_id,$case_id,$case_name,$sample_id,$sample_name,$path))."\n";
          push @{$report{"missing_rsems"}{$path}{join("\t", ($patient_id,$case_id))}}, join("\t", ($patient_id,$case_id,$case_name,$sample_id,$sample_name));
        }
      }
    }
  }
}
$sth_rna_smps->finish;
close(MISSING_RSEMS);

print("7: checking case_id <> case_name\n");
my $sth_case_consistence = $dbh->prepare("select distinct m.patient_id,m.case_id,m.case_name,c.path,c.version,m.match_type from sample_case_mapping m,processed_cases c where (m.case_id <> m.case_name or m.match_type like 'partial%') and c.patient_id not like 'CP0%' and c.patient_id=m.patient_id and c.case_id=m.case_id order by patient_id");
$sth_case_consistence->execute();

open(CASE_NAME_INCONSISTENCY, ">$out_dir/case_name_inconsistency.txt");
open(CASE_CONTENT_INCONSISTENCY, ">$out_dir/case_content_inconsistency.txt");
print CASE_NAME_INCONSISTENCY join("\t",("Patient_ID","Case_ID","Case_Name","Path","Version","Match_Type"))."\n";
print CASE_CONTENT_INCONSISTENCY join("\t",("Patient_ID","Case_ID","Case_Name","Path","Version","Match_Type"))."\n";
while (my ($patient_id,$case_id,$case_name,$path,$version,$match_type) = $sth_case_consistence->fetchrow_array) {
  if ($case_id ne $case_name) {
    print CASE_NAME_INCONSISTENCY join("\t", ($patient_id,$case_id,$case_name,$path,$version,$match_type))."\n";
    push @{$report{"case_name_inconsistency"}{$path}}, join("\t", ($patient_id,$case_id,$case_name,$path,$version,$match_type));
  }
  if ($match_type =~ /partial/) {
    print CASE_CONTENT_INCONSISTENCY join("\t", ($patient_id,$case_id,$case_name,$path,$version,$match_type))."\n";
    push @{$report{"case_content_inconsistency"}{$path}}, join("\t", ($patient_id,$case_id,$case_name,$path,$version,$match_type)); 
  }
}
close(CASE_NAME_INCONSISTENCY);
close(CASE_CONTENT_INCONSISTENCY);
$sth_case_consistence->finish;

print("8: checking sample_id discrepancy between master file and processed data\n");
my $sth_sample_consistence = $dbh->prepare("select distinct v.patient_id,v.case_id,v.sample_id,v.sample_name,c.path from var_samples v,processed_cases c where v.patient_id=c.patient_id and v.case_id=c.case_id and not exists(select * from samples s where v.sample_id=s.sample_id and v.sample_name=s.sample_name)");
$sth_sample_consistence->execute();

open(SAMPLE_INCONSISTENCY, ">$out_dir/sample_inconsistency.txt");
print SAMPLE_INCONSISTENCY join("\t",("Patient_ID","Case_ID","Sample_ID","Sample_Name", "Path"))."\n";
while (my ($patient_id,$case_id,$sample_id, $sample_name,$path) = $sth_sample_consistence->fetchrow_array) {
  $sample_name = "" if (!$sample_name);
  print SAMPLE_INCONSISTENCY join("\t", ($patient_id,$case_id,$sample_id, $sample_name,$path))."\n";
  push @{$report{"sample_inconsistency"}{$path}}, join("\t", ($patient_id,$case_id,$sample_id, $sample_name,$path));  
}
close(SAMPLE_INCONSISTENCY);
$sth_sample_consistence->finish;
$dbh->disconnect();

print("9: generating report\n");
my @emails = ('chouh@nih.gov','khanjav@mail.nih.gov','weij@mail.nih.gov','wenxi@mail.nih.gov','vineela.gangalapudi@nih.gov','patrick.zhao@nih.gov','erica.pehrsson@nih.gov');
my @compass_emails = ('chouh@nih.gov','manoj.tyagi@nih.gov','kristin.valdez@nih.gov');

&generateReport("Khanlab",\%report, \@emails);
&generateReport("COMPASS",\%report, \@compass_emails);

sub generateReport {
  my ($target, $report_ref, $recipient_ref) = @_;
  my $report = \%{$report_ref};  
  my @header = ("Category");
  my @prjs = sort keys %project_mapping;
  foreach my $prj (@prjs) {
    next if ($target eq "Khanlab" && $prj =~ /compass/);
    next if ($target ne "Khanlab" && $prj !~ /compass/);
    push @header, $prj;
  }
  my @content = ();
  foreach my $cat (sort keys %report) {
    next if ($target ne "Khanlab" && ($cat eq "case_name_inconsistency" || $cat eq "case_content_inconsistency"));
    my $cat_label = ucfirst($cat);    
    $cat_label =~ s/_/ /g;
    my @row = ($cat_label);
    foreach my $prj (@prjs) { 
      next if ($target eq "Khanlab" && $prj =~ /compass/);
      next if ($target ne "Khanlab" && $prj !~ /compass/);
      my $cnt = 0;
      if (exists $report{$cat}{$prj}) {
        if ($cat eq "missing_rsems" || $cat eq "unprocessed_cases") {
          $cnt = keys %{$report{$cat}{$prj}};
        } else {
          $cnt = @{$report{$cat}{$prj}};
        }
      }
      push @row, $cnt;
    }
    push @content, \@row;
  }

  open(SUMMARY, ">$out_dir/summary_$target.txt");
  print SUMMARY join("\t",@header)."\n";
  my $subject = "Data integrity report - $target";
  my $html = "<H3>$subject</H3><table border=1 cellspacing=1 width=60%><tr><th>".join("</th><th>", @header)."</th></tr>";
  foreach my $c (@content) {
    my @row = @{$c};
    print SUMMARY join("\t",@row)."\n";
    $html .= "<tr><td>".join("</td><td>", @row)."</td></tr>";
  }
  close(SUMMARY);
  $html .= "</table><H4>See the details <a href='$production_url/viewDataIntegrityReport/$target'>here</a></H4>";
  my $explanation = qq{
  <H3>Explanation:</H3>
  <H4 style="color:red">Cases on Biowulf only</H4>
  <b>Description:</b> Cases found on Biowulf only<br>
  <b>Possible reasons:</b> 1. Old cases 2. The sync was failed<br>
  <b>Actions:</b> 1. Delete the cases on Biowulf 2. Re-sync the cases<br>
  <H4 style="color:red">Cases on Frederick only</H4>
  <b>Description:</b> Cases found on Frederick only<br>
  <b>Possible reasons:</b> Failed cases on Biowulf<br>
  <b>Actions:</b> Delete the cases on Frederick<br>};
  my $explanation2 = qq{
  <H4 style="color:red">Case content inconsistency</H4>
  <b>Description:</b> Samples processed does not match samples defined in master file<br>
  <b>Possible reasons:</b> Case definition was changed in master file<br>
  <b>Actions:</b> Check master file or reprocess the cases<br>
  <H4 style="color:red">Case name inconsistency</H4>
  <b>Description:</b> Case name is not the same as case ID (folder name)<br>
  <b>Possible reasons:</b> Case name was changed in master file or cases were not processed properly<br>
  <b>Actions:</b> 1. Rename the folder 2. Check master file 3. reprocess the cases<br>
  <H4 style="color:red">Sample inconsistency</H4>  
};
  my $explanation3 = qq{
  <H4 style="color:red">Missing BAMs</H4>
  <b>Description:</b> BAM files not found<br>
  <b>Possible reasons:</b> 1. Pipeline was not finished properly 2. syncing was failed<br>
  <b>Actions:</b> 1. Check the BAM files on Biowulf 2. Remake squeeze bam and touch the successful.txt<br>
  <H4 style="color:red">Missing RSEMs</H4>
  <b>Description:</b> RSEM files not found<br>
  <b>Possible reasons:</b> Cases too old<br>
  <b>Actions:</b> Reprocess the cases<br>
  <H4 style="color:red">Sample inconsistency</H4>
  <b>Description:</b> Sample ID/name in processed data is different from master file<br>
  <b>Possible reasons:</b> FCID has been added/changed after cases were uploaded<br>
  <b>Actions:</b> Reprocess the cases<br>
  <H4 style="color:red">No successful cases</H4>
  <b>Description:</b> Cases has no successful.txt<br>
  <b>Possible reasons:</b> Old Cases<br>
  <b>Actions:</b> 1. check if cases should be deleted 2. Touch the successful.txt<br>
  <H4 style="color:red">Unloaded cases</H4>
  <b>Description:</b> Cases were synced but not in database<br>
  <b>Possible reasons:</b> 1. Cronjob issue 2. Database issue<br>
  <b>Actions:</b> 1. Load the case manually<br>
  <H4 style="color:red">Unprocessed cases</H4>
  <b>Description:</b> Cases defined in master file but not processed<br>
  <b>Possible reasons:</b> 1. Cases to be processed 2. Cases failed 3. Forgotten cases 4. Not main pipeline cases<br>
  <b>Actions:</b> 1. check if cases are failed 2. Reprocess the cases<br>
  <H4 style="color:red">Unused cases</H4>
  <b>Description:</b> Cases were processed but could not find the match in master file<br>
  <b>Possible reasons:</b> Case definition was changed in master file<br>
  <b>Actions:</b> Check if cases should be deleted<br>
  <b>Description:</b> Sample ID/name is not the same as master file<br>
  <b>Possible reasons:</b> Sample ID (Library ID or flowcell ID) was changed in master file or cases were not processed properly<br>
  <b>Actions:</b> 1. Reload the case 2. Check master file 3. reprocess the cases<br>  
};

my $data = ($target eq "Khanlab")? $html.$explanation.$explanation2.$explanation3 : $html.$explanation.$explanation3;

my $recipients = join(",", @{$recipient_ref});
my $sender    = 'oncogenomics@mail.nih.gov';  
my $mime = MIME::Lite->new(
      'From'    => $sender,
      'To'      => $recipients,
      'Subject' => $subject,
      'Type'    => 'text/html',
      'Data'    => $data,
  );
  $mime->send();
}

