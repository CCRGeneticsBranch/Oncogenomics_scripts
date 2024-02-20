#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use Getopt::Long qw(GetOptions);
use File::Basename;
use Try::Tiny;
use MIME::Lite; 
use JSON;
local $SIG{__WARN__} = sub {
	my $message = shift;
	if ($message =~ /uninitialized/) {
		die "Warning:$message";
	}
};

my $input_file_list;
my $modified_flag_list;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -i  <string>  Input text files (comma separated)
  
__EOUSAGE__



GetOptions (
  "i=s" => \$input_file_list
);
my $script_dir = dirname(__FILE__);

my $cmd = "php $script_dir/getDBConfig.php";
my @db_config = readpipe($cmd);
my ($host, $sid, $username, $passwd) = split(/\t/, $db_config[0]);
my @input_files = split(/,/, $input_file_list);

my @duplicate_errors=&checkDuplicates(@input_files);
print @duplicate_errors."\n";
my @type_errors=&checkSeqandEnrichTypes(@input_files);
push (@duplicate_errors,@type_errors);
&makeEmail(@duplicate_errors);



sub checkDuplicates{
  my @input_files=@_;
  my %project_samples = ();
  my @errors=();
  for (my $file_idx=0; $file_idx<=$#input_files; $file_idx++) {
    my $input_file = $input_files[$file_idx]; 
    open(IN_FILE, "$input_file") or die "Cannot open file $input_file";
    my $line = <IN_FILE>;
    chomp $line;
    my @headers = split(/\t/,$line);
    my %header_idx = ();
    my $idx = 0;
    foreach my $header(@headers) {
      $header_idx{$header} = $idx++;
    }

    my $num_fields = $#headers;
    while (<IN_FILE>) {
      chomp;
      my @fields = split(/\t/);
      #next if ($#fields < $num_fields);
      next if ($#fields == 0);
      # clear NA fields
      for (my $i = 0; $i<=$#fields; $i++) {
        $fields[$i] = "" unless defined($fields[$i]);   
        if ($fields[$i] eq "#N/A!" || $fields[$i] eq "#N/A" || $fields[$i] eq "Unknown" || $fields[$i] eq "0") {
          $fields[$i] = "";
        }
      }
      my $lib_id = $fields[$header_idx{"Library ID"}];
      my $cus_id = $fields[$header_idx{"custom ID"}];

      if (defined $lib_id && $lib_id ne"" ){
        if (exists($project_samples{$lib_id." ".$cus_id})){
          my $error=$input_file."\t".$lib_id."\tDuplication errror for patient $cus_id";
          push @errors,$error;
          print $error."\n";
          
        }
        else{
#          my $error=$input_file."\t".$lib_id."\tDuplication errror";
 #         push @errors,$error;
          $project_samples{$lib_id." ".$cus_id} = 1
        }
      }
      
    }
  }
  print "Checked for duplicates\n";
  return @errors;
}
sub getSeqTypes{
  my $seq=$_[0];
  my $data=$_[1];
  my @type=();
  for ( @{$data->{SeqTypes}{$seq}} ) {
    push @type,$_;
  }
  return @type;
}

sub checkSeqandEnrichTypes{
  my $json_file = "$script_dir/master_ver_steps.json";
  my @ensteps=();
  my $json_text = do {
  open(my $json_fh, "<:encoding(UTF-8)", $json_file)
      or die("Can't open \$json_file\": $!\n");
    local $/;
    <$json_fh>
  };

  my $json = JSON->new;
  my $data = $json->decode($json_text);
  my @Ts=getSeqTypes('Ts',$data);
  my @Es=getSeqTypes('Es',$data);
  my @Ps=getSeqTypes('Ps',$data);
  my @Cs=getSeqTypes('Cs',$data);
  my @Ws=getSeqTypes('Ws',$data);
  my @Ms=getSeqTypes('Ms',$data);

for ( @{$data->{EnSteps}} ) {
    push @ensteps,$_;
}
  my @input_files=@_;
  my %project_samples = ();
  my @errors=();

  for (my $file_idx=0; $file_idx<=$#input_files; $file_idx++) {
    my $input_file = $input_files[$file_idx];
    my @input_file_name = split(/\//, $input_file);
 
    open(IN_FILE, "$input_file") or die "Cannot open file $input_file";
    my $line = <IN_FILE>;
    chomp $line;
    my @headers = split(/\t/,$line);
    my %header_idx = ();
    my $idx = 0;
    foreach my $header(@headers) {
      $header_idx{$header} = $idx++;
    }

    my $num_fields = $#headers;
    while (<IN_FILE>) {
      chomp;
      my @fields = split(/\t/);
      next if ($#fields == 0);
      for (my $i = 0; $i<=$#fields; $i++) {
        $fields[$i] = "" unless defined($fields[$i]);   
        if ($fields[$i] eq "#N/A!" || $fields[$i] eq "#N/A" || $fields[$i] eq "Unknown" || $fields[$i] eq "0") {
          $fields[$i] = "";
        }
      }

      my $suffix="";
      my $lib_id = $fields[$header_idx{"Library ID"}];
      my $en_step = $fields[$header_idx{"Enrichment step"}];
      my $seq_type = $fields[$header_idx{"Type of sequencing"}];
      my $fcid = $fields[$header_idx{"FCID"}];
      my $incorrect="";
      my $error="";
      $error=&checkEnrichment($en_step);
      if ($error ne "" and defined $lib_id){
           $error=$input_file_name[9]."\t".$lib_id."\tLibrary ID ".$error;
           push @errors,$error;
           $error="";
      }
      $error=&checkFCID($fcid);
      if ($error ne "" and defined $lib_id and $lib_id ne ""){
           $error=$input_file_name[9]."\t".$lib_id."\tLibrary ID ".$error;
           push @errors,$error;
           $error="";
      }
      if (defined $lib_id){
        if (index($seq_type, "T-il") != -1){
          foreach $suffix(@Ts){
            if(index($lib_id, $suffix) != -1){
              $incorrect="False";
              last;
            }
          }
          if(index($lib_id, "_") == -1){
             $incorrect="False";
          }
        }
        elsif (index($seq_type, "E-il") != -1){
          foreach $suffix(@Es){
            if(index($lib_id, $suffix) != -1){
              $incorrect="False";
              last;
            }
            else{
              $incorrect="True";
            }
          }
          if(index($lib_id, "_") == -1){
             $incorrect="False";
          }
          

          
        }
        elsif (index($seq_type, "P-il") != -1){
          foreach $suffix(@Ps){
            if(index($lib_id, $suffix) != -1){
              $incorrect="False";
              last;
            }
          }
          if(index($lib_id, "_") == -1){
             $incorrect="False";
          }
          
        }
        elsif (index($seq_type, "WG-il") != -1){
          foreach $suffix(@Ws){
            if(index($lib_id, $suffix) != -1){
              $incorrect="False";
              last;
            }
          }
          if(index($lib_id, "_") == -1){
             $incorrect="False";
          }
          
        }
        elsif (index($seq_type, "M-il") != -1){
          foreach $suffix(@Ms){
            if(index($lib_id, $suffix) != -1){
              $incorrect="False";
              last;
            }
          }
          
        }
        elsif (index($seq_type, "C-il") != -1){
          foreach $suffix(@Cs){
            if(index($lib_id, $suffix) != -1){
              $incorrect="False";
              last;
            }
          }
          
        }
       if ($incorrect eq"True"){
        if (index($seq_type, "E-il") != -1 && $lib_id eq"130TSeqCap_E"){
          print "FINAL ".$incorrect." $lib_id\n";
        }
          my $error=$input_file_name[9]."\t".$lib_id."\tLibrary ID ".$lib_id." has incorrect type of sequencing ".$seq_type;
           push @errors,$error;
       }
      }
      
      
    }
  }
  print "Checked Experiment\n";
  return @errors;
}
sub checkEnrichment{
  my $en_step=$_[0];
  my $error="";
  if (defined $en_step){
      my $error="";
  }
  else{
    $error="has no enrichment step";
  }
  
  return $error;

}

sub checkFCID{
  my $fcid=$_[0];
  my $error="";
  if (defined $fcid && length($fcid)==9){
      my $error="";
  }
  else{
    $error="has an incorrect flow cell ID";
  }
  
  return $error;

}


sub sendEmail {
  my ($content, $recipient) = @_;
  my $subject   = 'OncogenomicsDB master file verification errors';
  my $sender    = 'oncogenomics@mail.nih.gov';
  
  my $mime = MIME::Lite->new(
      "From"    => $sender,
      "To"      => $recipient,
      "Subject" => $subject,
      "Type"    => "text/html",
      "Data"    => $content,
  );

  $mime->send();
}

sub makeEmail{
  my @errors=@_;
 # print @{$_};
  my $content = "<H4>The following errors occur in the master file</H4>"."<table id='errlog' border=1 cellspacing=2 width=80%>
    <thead><tr><th>Input file</th><th>Sample ID</th><th>Error</th></tr></thead>";
  my $count=0;
  foreach (@_){
#    print $_;
    foreach my $err ($_) {
      $content .= "<tr>";
      my @fields = split(/\t/, $err);
      foreach my $field (@fields) {
        $content .= "<td>$field</td>";
      }
      $count++;
#      print " ".$count."\n";
    }
    if ($count==10){
  #      $count=0;
    #    last;
      }
  }

  $content .= "</tr></tbody></table>";
  print $count."\n";
  if($count>0){
    &sendEmail($content, 'wenxi@mail.nih.gov,vuonghm@mail.nih.gov,songyo@mail.nih.gov,weij@mail.nih.gov');
  }
}

