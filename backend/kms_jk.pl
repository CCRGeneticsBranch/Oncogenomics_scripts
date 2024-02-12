#!/usr/bin/perl
use strict;
use CGI qw(param header -no_debug);
use CGI::Carp qw(fatalsToBrowser);
use DBI;
#use Statistics::LogRank;
$| = 1;

unless (@ARGV) {
  my $db = param("db");
  my $gene_id = param("geneid");
  my $user_id = param("user_id");
  my $kms_cutoff = param("kms_cutoff"); 
  generate_gif($db,$gene_id,$user_id,$kms_cutoff);
}
else {
  generate_data();
}
#print STDERR "kms_cutoff:-->".$kms_cutoff;
#$db = 'nbProgGm';
#$user_id = 690;
#$gene_id = 677;
sub generate_gif{
  my ($db,$gene_id,$user_id,$kms_cutoff) = @_;
=comments
  my $hi_exp_censor = "/WWW/htdocs/images/temp/kms_hiexp_censor_".$user_id.".dat";
  my $lo_exp_censor = "/WWW/htdocs/images/temp/kms_loexp_censor_".$user_id.".dat";
  my $avg_exp_censor = "/WWW/htdocs/images/temp/kms_avgexp_censor_".$user_id.".dat";
  my $hi_exp_plot = "/WWW/htdocs/images/temp/kms_hiexp_".$user_id.".dat";
  my $lo_exp_plot = "/WWW/htdocs/images/temp/kms_loexp_".$user_id.".dat";
  my $avg_exp_plot = "/WWW/htdocs/images/temp/kms_avgexp_".$user_id.".dat";
=cut
  #system "$0 $db $gene_id $user_id $kms_cutoff $hi_exp_censor $lo_exp_censor $avg_exp_censor $hi_exp_plot $lo_exp_plot $avg_exp_plot";
  #exit(0);
  print header('image/gif');
  open (GP, '| /usr/local/bin/gnuplot') || die "open: $!";
  while (<DATA>) {
    print GP $_;
  }
  #system "$0 $db $gene_id $user_id $kms_cutoff $hi_exp_censor $lo_exp_censor $avg_exp_censor $hi_exp_plot $lo_exp_plot $avg_exp_plot";
  print GP "plot '<$0 $db $gene_id $kms_cutoff H E'";
  print GP "ls 3 title \"High-Expression\" with lines,";
  print GP "'<$0 $db $gene_id $kms_cutoff H C'";
  print GP "ls 4 notitle, ";
  print GP "'<$0 $db $gene_id $kms_cutoff L E'";
  print GP "ls 5 title \"Low-Expression\" with lines, ";
  print GP "'<$0 $db $gene_id $kms_cutoff L C'";
  print GP "ls 6 notitle, ";
  print GP "'<$0 $db $gene_id $kms_cutoff A E'";
  print GP "ls 1 title \"All-Samples\" with lines, ";
  print GP "'<$0 $db $gene_id $kms_cutoff A C'";
  print GP "ls 2 notitle";
  close GP;
}
sub generate_data{  
    my ($db,$gene_id,$kms_cut,$grp,$mod) = @ARGV; #grp:hi-exp;lo-exp;avg-exp; mod:exp;censor;
    
    my $dbh=DBI->connect('dbi:mysql:database=JK;host=10.133.27.151', 'JK_web', 'JK@web0', );

    #---------get data from sample_info----------------------
    my $qry = "select patient_id,efs_day,event from $db\_sample_info";
    my $sql = $dbh->prepare($qry);
    $sql->execute;
    my $eve = $sql->fetchall_arrayref;

    #---------get data from sample---------------------------
    $qry = "select patient_id from $db\_sample order by sample_id ASC";
    #$qry = "select s.patient_id, s.sample_id from $db\_sample as s join $db\_sample_info as i on i.patient_id=s.patient_id order by sample_id ASC";
    $sql = $dbh->prepare($qry);
    $sql->execute;
    my $sample = $sql->fetchall_arrayref;

    #-----------info----------------------
    my %tmp_info;
    foreach (@$eve){
      $tmp_info{$$_[0]} = [$$_[1],$$_[2]];
    } 
    my %info;
    my $ct = 1;
    #open(MYFILE, '>/tmp/hjb.txt');
    for (my $i = 0; $i<@$sample; $i++){ 
    #  print MYFILE scalar(keys %info), "\t", $i, "\t", $ct, "\t", $$sample[$i][0], "\n";
      $info{$ct} = $tmp_info{$$sample[$i][0]} if $tmp_info{$$sample[$i][0]};
      $ct++;
    }
    #close (MYFILE);

    #---------get data from exprs----------------------------
    my $qry = "select log2ctr from $db\_exprs where gene_id = ?";
    my $sql = $dbh->prepare($qry);
    $sql->execute($gene_id);
    my $exprs = $sql->fetchrow_array;


    #$qry = "select min(efs_day),max(efs_day) from $db\_sample_info";
    #$sql = $dbh->prepare($qry);
    #$sql->execute;
    #my ($min_efs,$max_efs) = $sql->fetchrow_array;
    
    #-----------exprs---------------------
    my @vals = split(/\,/,$exprs);
    my $ct = 1;
    my $ii = 0;
    my %exprs;
    #remove the data without survivial information
    foreach (@vals){
      $exprs{$ct} = $_ if $info{$ct};
      $ct++;
    } 


    if ($grp eq "H"){
      my ($hi_exp_grp,$lw_exp_grp) = &get_two_grps($kms_cut,\%exprs,\%info);      
      &get_kms_plot($hi_exp_grp,\%info,$mod);
    }
    elsif ($grp eq "L"){
      my ($hi_exp_grp,$lw_exp_grp) = &get_two_grps($kms_cut,\%exprs,\%info);      
      &get_kms_plot($lw_exp_grp,\%info,$mod);
    }
    else{
      my @avg_exp_grp = sort {$info{$a}[0]<=>$info{$b}[0]} keys %info;   
      &get_kms_plot(\@avg_exp_grp,\%info,$mod);
    }
    $sql->finish;
    $dbh->disconnect;
}

sub get_kms_plot{
  my ($grp,$inf,$mod) = @_;
  my ($s,$c) = 0;
  my $frac = 1;
  my $total = @$grp;
  my @plot;
  my @plot_c;
  my $ini_d = -1;
  my @c_tmp;
  foreach my $idx (@$grp) { #use @grp as an index to parse through %exp and %inf
    if ($$inf{$idx}[1] eq "A"){
       $c++;
       push @c_tmp, $idx;
    }
    else {
      $s = $total;
      $total = $s - $c -1;
      my $fraction = ($s - $c - 1) / (($s - $c)||1) * $frac;
      $fraction = $frac if $fraction == 0;
      #push @plot, [$ini_d,$frac] if $ini_d >= 0;
      push @plot, [$$inf{$idx}[0],$frac];
      push @plot, [$$inf{$idx}[0],$fraction];
      $ini_d = $$inf{$idx}[0];
      if (@c_tmp){
        foreach (@c_tmp){
          push @plot_c, [$$inf{$_}[0],$frac];
	}
      }
      $frac = $fraction;
      @c_tmp = ();
      $c = 0;
    }
  }
  #foreach (@plot){
  #  print STDERR "$$_[0]\t$$_[1]\n";
  #}
  #if ($plot[0][0] == 0){
  #  my $second = [$plot[1][0],$plot[0][1]];
  #  my $first = shift @plot;
  #  unshift @plot,$second;
  #  unshift @plot,$first;
  #}
  #else {
  #   unshift @plot,[0,$plot[0][1]] if $plot[0][0] != 0;
    #}
  #foreach (@plot){
  #  print STDERR "$$_[0]\t$$_[1]\n";
  #}
  my @tmp_plot = @plot;
  my $tmp = pop @tmp_plot;
  my $plot_last_day =$$tmp[0];
  my $last_idx = pop @$grp;
  my $real_last_day = $$inf{$last_idx}[0];
  #print STDERR "DATE===> $plot_last_day    $real_last_day";
  if ($plot_last_day < $real_last_day){
    push @plot,[$real_last_day,$frac];
    foreach (@c_tmp){
      push @plot_c, [$$inf{$_}[0],$frac];
    }
  }
  unshift @plot,[0,$plot[0][1]] if $plot[0][0] != 0;
  if ($mod eq "E"){
    for (my $i = 0; $i<@plot; $i++){
      print $plot[$i][0]."\t".$plot[$i][1]."\n";
    }
  }
  else{
    for (my $i = 0; $i<@plot_c; $i++){
      print $plot_c[$i][0]."\t".$plot_c[$i][1]."\n";
    }
  }
}
=comments
sub get_pval{
  my ($g1,$g2,$min_efs,$max_efs,$info) = @_;
  my ($g1_s,$g1_d) = &get_two_grp2($g1,$min_efs,$max_efs,$info);
  my ($g2_s,$g2_d) = &get_two_grp2($g2,$min_efs,$max_efs,$info);
  my $log_rank = new Statistics::LogRank;
  $log_rank->load_data('hi_exp_grp survs',@$g1_s);
  $log_rank->load_data('hi_exp_grp deaths',@$g1_d);
  $log_rank->load_data('lw_exp_grp survs',@$g2_s);
  $log_rank->load_data('lw_exp_grp deaths',@$g2_d);
  my ($log_rank_stat,$p_value) = $log_rank->perform_log_rank_test('hi_exp_grp survs','hi_exp_grp deaths','lw_exp_grp survs','lw_exp_grp deaths');
  return $log_rank_stat,$p_value;
}
=cut

sub get_two_grps{
  my ($cut,$exprs,$info) = @_;
  my @hi_tmp;
  my @lw_tmp;
  foreach (keys %$exprs){
    if ($$exprs{$_}>=$cut){
       push @hi_tmp,$_;
    }
    else{
       push @lw_tmp,$_;
    }
  }
  my %tmp;
  foreach (@hi_tmp){
    $tmp{$_} = $$info{$_}[0] if $$info{$_}[0];
  }
  my @hi_exp_grp = sort {$tmp{$a}<=>$tmp{$b}} keys %tmp; 
  #foreach (@hi_exp_grp){
  #  print $info{$_}[0]."\n";
  #}
  my %tmp2;
  foreach (@lw_tmp){
    $tmp2{$_} = $$info{$_}[0] if $$info{$_}[0];
  }
  my @lw_exp_grp = sort {$tmp2{$a}<=>$tmp2{$b}} keys %tmp2; 
  #foreach (@hi_exp_grp) {
  #   print $_, "\t", $$exprs{$_}, "\n"; 
  #}
  #foreach (@lw_exp_grp) {
  #   print $_, "\t", $$exprs{$_}, "\n"; 
  #}


  return \@hi_exp_grp,\@lw_exp_grp;
}


__DATA__
set term gif size 800,450
set title "Kaplan-Meier Survival Estimation" font "arial,18"
set xlabel "Time (day)"
set ylabel "Probability of Survival"
set key bottom left
set key box
set border
set yrange [0:1]
set style line 1  linetype 0 linecolor rgb "#AAAAAA"  linewidth 3.000 pointtype 0 pointsize default 
set style line 2  linetype 27 linecolor rgb "#AAAAAA" linewidth 1.000 pointtype 27 pointsize default
set style line 3  linetype 2 linecolor rgb "#CC0000"  linewidth 3.000 pointtype 2 pointsize default
set style line 4  linetype 27 linecolor rgb "#CC0000" linewidth 1.000 pointtype 27 pointsize default
set style line 5  linetype 3 linecolor rgb "#0000FF"  linewidth 3.000 pointtype 3 pointsize default
set style line 6  linetype 27 linecolor rgb "#0000FF" linewidth 1.000 pointtype 27 pointsize default

