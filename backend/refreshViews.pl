#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';
use Time::Piece;
require(dirname(abs_path($0))."/../lib/Onco.pm");

my $refresh_all = 0;
my $do_cnv = 0;
my $do_prj_summary = 0;
my $do_avia = 0;
my $do_avia_full = 0;
my $do_cohort = 0;
my $show_sql = 0;

my $usage = <<__eousage__;

usage:

$0 [options]

options:

  -a            refresh all
  -c            refresh cnv views
  -p            refresh project views
  -v            refresh avia views
  -f            refresh full avia views
  -h            refresh cohort views
  -s            show sql statement
  
__eousage__



GetOptions (
  'a' => \$refresh_all,
  'c' => \$do_cnv,
  'p' => \$do_prj_summary,
  'v' => \$do_avia,
  'f' => \$do_avia_full,
  'h' => \$do_cohort,
  's' => \$show_sql
);

my $cases = <<'end';
select distinct c.*,s.case_name from sample_case_mapping s,processed_cases c where s.patient_id=c.patient_id and s.case_id=c.case_id;
end
my $fusion_count = <<'end';
select s.patient_id, s.case_name, s.case_id, count(*) as fusion_cnt from var_fusion v, sample_cases s where v.patient_id=s.patient_id and v.sample_id=s.sample_id group by s.patient_id, s.case_name, s.case_id;
end
my $processed_sample_cases = <<'end';
select distinct s.patient_id,s.sample_id, c.case_name,c.case_id, c.path, s.sample_name, s.sample_alias, s.exp_type, s.tissue_cat, v.type,count(*) as var_cnt 
from samples s, cases c, var_samples v
where s.sample_id=v.sample_id and v.patient_id=c.patient_id and v.case_id=c.case_id
group by s.patient_id,s.sample_id, c.case_name,c.case_id, c.path, s.sample_name, s.sample_alias, v.type,s.exp_type, s.tissue_cat;
end
my $project_cases = <<'end';
select distinct p.project_id,p.patient_id,s.case_name,s.case_id from project_samples p, sample_cases s where p.sample_id=s.sample_id and 
  not exists(select * from project_case_blacklist b where p.name=b.project and s.patient_id=b.patient_id and s.case_name=b.case_name);
end
my $project_diagnosis_gene_tier = <<'end';
select project_id, diagnosis, gene,type,'germline' as tier_type, germline_level  as tier, count(patient_id) as cnt from (select distinct p.project_id, p2.diagnosis, v.gene, v.type, p.patient_id, v.germline_level from var_gene_tier v, project_patients p, patients p2
  where p.patient_id=p2.patient_id and p.patient_id=v.patient_id) co
  group by project_id,diagnosis, gene,type,germline_level
  union
  select project_id, diagnosis, gene,type,'somatic' as tier_type, somatic_level as tier, count(patient_id) as cnt from (select distinct p.project_id, p2.diagnosis, v.gene, v.type, p.patient_id, v.somatic_level from var_gene_tier v, project_patients p, patients p2
  where p.patient_id=p2.patient_id and p.patient_id=v.patient_id) co
  group by project_id,diagnosis, gene,type,somatic_level;
end
my $project_gene_tier = <<'end';
select project_id, gene,type,'germline' as tier,germline_level as tier_type, count(patient_id) as cnt from (select distinct p.project_id, v.gene, v.type, p.patient_id, v.germline_level from var_gene_tier v, project_patients p
  where p.patient_id=v.patient_id) co1
  group by project_id,gene,type,germline_level
  union
  select project_id, gene,type,'somatic' as tier,somatic_level as tier_type, count(patient_id) as cnt from (select distinct p.project_id, v.gene, v.type, p.patient_id, v.somatic_level from var_gene_tier v, project_patients p
  where p.patient_id=v.patient_id) co2
  group by project_id,gene,type,somatic_level;
end

my $project_mview = <<'end';
select distinct id,name,description,ispublic,patients,cases,samples,processed_patients,processed_cases,version,survival,exome,panel,rnaseq,whole_genome,status,user_id,created_by,updated_at from 
        (select p1.id, p1.name, p1.description, p1.ispublic, 
          (select count(distinct patient_id) from project_cases s where p1.id=s.project_id) as patients,
                  (select count(distinct case_name) from project_cases s where p1.id=s.project_id) as cases,
                  (select count(distinct sample_id) from project_samples s where p1.id=s.project_id) as samples,
          (select count(distinct patient_id) from project_processed_cases s where p1.id=s.project_id) as processed_patients,
                  (select count(distinct case_id) from project_processed_cases s where p1.id=s.project_id) as processed_cases,
                  version,
          (select count(distinct c1.patient_id) from project_patients c1, patient_details c2 where p1.id=c1.project_id and c1.patient_id=c2.patient_id and class='overall_survival') as survival,
          (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='exome') as exome,
          (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='panel') as panel,
          (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='rnaseq') as rnaseq,
          (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='whole genome') as whole_genome,
          status, p1.user_id, u.email as created_by, p1.updated_at
           from projects p1 left join users u on p1.user_id=u.id,project_samples p2 where p1.id=p2.project_id) projects where (rnaseq is not null or whole_genome is not null or exome is not null or panel is not null or panel is not null or whole_genome is not null);
end
my $project_patient_summary = <<'end';
select p.project_id, name, count(distinct p.patient_id) as patients from project_patients p, var_samples s where p.patient_id=s.patient_id group by p.project_id, name;
end
my $project_patients = <<'end';
select distinct p.*,project_id,name from patients p, samples s1, project_sample_mapping s2,projects j where j.id=s2.project_id and s1.sample_id=s2.sample_id and s1.patient_id=p.patient_id;
end
my $project_processed_cases = <<'end';
select distinct p.project_id,p.patient_id,p.case_name,c.case_id,c.path,c.version,c.genome_version from project_cases p, processed_cases c 
where p.patient_id=c.patient_id and p.case_id=c.case_id;
end
my $project_sample_summary = <<'end';
select project_id, count(distinct s.sample_id) as samples, exp_type from project_patients p, var_samples s where p.patient_id=s.patient_id group by project_id,exp_type;
end
my $project_samples = <<'end';
select distinct s1.*,project_id,name,diagnosis from samples s1, project_sample_mapping s2,projects j,patients p where j.id=s2.project_id and s1.sample_id=s2.sample_id and s1.patient_id=p.patient_id;
end
my $sample_cases = <<'end';
select distinct s.*,m.case_name,c.case_id,c.path from samples s,sample_case_mapping m left join cases c on m.patient_id=c.patient_id and m.case_name=c.case_name where m.sample_id=s.sample_id;
end
my $user_projects = <<'end';
select distinct * from (
(select distinct p.id as project_id, p.name as project_name, g.user_id,p.ispublic from project_group_users g, projects p 
where p.project_group=g.project_group) 
union
(select distinct p.id as project_id, p.name as project_name, u.id as user_id,p.ispublic from users u, users_groups g, projects p where (u.id=g.user_id and g.group_id=p.id) or p.ispublic=1)
union
(select  p.id as project_id, p.name as project_name, u.user_id as user_id,p.ispublic from users_permissions u, projects p where u.perm='_superadmin')
) u;
end
my $var_cases = <<'end';
  select distinct v.*,c.path,c.case_name from var_type v,cases c where v.patient_id=c.patient_id and v.case_id=c.case_id;
end
my $var_cnv_genes_hg19 = <<'end';
select v.*, g.symbol as gene, c.case_name,s.sample_name 
from cases c, samples s, var_cnv v left join gene g on 
v.chromosome=g.chromosome and 
v.end_pos >= g.start_pos and 
v.start_pos <= g.end_pos and 
g.species='hg19' and 
g.type='protein_coding'
where 
v.patient_id=c.patient_id and 
v.case_id=c.case_id and 
v.sample_id=s.sample_id and
c.genome_version='hg19';
end
my $var_cnv_genes_hg38 = <<'end';
select v.*, g.symbol as gene, c.case_name,s.sample_name 
from cases c, samples s, var_cnv v left join gene g on 
v.chromosome=g.chromosome and 
v.end_pos >= g.start_pos and 
v.start_pos <= g.end_pos and 
g.species='hg38' and 
g.type='protein_coding'
where 
v.patient_id=c.patient_id and 
v.case_id=c.case_id and 
v.sample_id=s.sample_id and
c.genome_version='hg38';
end
my $var_cnvkit_genes_hg19 = <<'end';
select v.*, g.symbol as gene, c.case_name,s.sample_name 
from cases c, samples s, var_cnvkit v left join gene g on  
v.chromosome=g.chromosome and 
v.end_pos >= g.start_pos and 
v.start_pos <= g.end_pos and 
g.species='hg19' and 
g.type='protein_coding'
where
v.patient_id=c.patient_id and 
v.case_id=c.case_id and 
v.sample_id=s.sample_id and
c.genome_version='hg19';
end
my $var_cnvkit_genes_hg38 = <<'end';
select v.*, g.symbol as gene, c.case_name,s.sample_name 
from cases c, samples s, var_cnvkit v left join gene g on  
v.chromosome=g.chromosome and 
v.end_pos >= g.start_pos and 
v.start_pos <= g.end_pos and 
g.species='hg38' and 
g.type='protein_coding'
where
v.patient_id=c.patient_id and 
v.case_id=c.case_id and 
v.sample_id=s.sample_id and
c.genome_version='hg38';
end
my $var_count = <<'end';
  select chromosome, start_pos, end_pos, type, count(distinct patient_id) as patient_count from var_samples where type = 'germline' or type = 'somatic' group by chromosome, start_pos, end_pos, type;
end
my $var_aa_cohort_oc = <<'end';
select project_id, gene, aa_site, type,count(patient_id) as cnt from (select distinct project_id, p2.patient_id,
  gene, canonicalprotpos as aa_site, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id) co
  group by project_id, gene, aa_site, type;
end
my $var_diagnosis_aa_cohort = <<'end';
select project_id, diagnosis, gene, aa_site, type,count(patient_id) as cnt from (select distinct project_id, p2.diagnosis, p2.patient_id,
  gene, canonicalprotpos as aa_site, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id) co
  group by project_id, diagnosis, gene, aa_site, type;
end
my $var_diagnosis_gene_cohort = <<'end';
select project_id, diagnosis, gene, type,count(patient_id) as cnt from (select distinct project_id, p2.diagnosis, p2.patient_id,
  gene, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id) co
  group by project_id, diagnosis, gene, type;
end
my $var_gene_cohort = <<'end';
select project_id, gene, type,count(patient_id) as cnt from (select distinct project_id, p2.patient_id,
  gene, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id) co
  group by project_id, gene, type;

end
my $var_gene_tier = <<'end';
select distinct p1.patient_id, p1.type, p1.gene, canonicalprotpos, germline_level, somatic_level from var_tier_avia p1,
  var_sample_avia_oc a where
  p1.chromosome=a.chromosome and
  p1.start_pos=a.start_pos and
  p1.end_pos=a.end_pos and
  p1.ref=a.ref and
  p1.alt=a.alt and p1.gene is not null;
end
my $var_genes = <<'end';
select distinct s.patient_id, s.sample_id, s.exp_type, s.tissue_cat, s.normal_sample, s.rnaseq_sample, a.gene, a.type
from samples s,var_sample_avia_oc a
where
s.sample_id=a.sample_id;
end
my $var_tier_avia_count = <<'end';
select patient_id,case_id,sample_id,type,germline_level,somatic_level,count(*) as cnt from var_tier_avia group by patient_id,case_id,sample_id,type,germline_level,somatic_level;
end
my $var_top20 = <<'end';
select * from (select gene, count(distinct patient_id) as patient_count, 'germline' as type from var_genes where type='germline' group by gene order by patient_count desc ) g where rownum <= 20 union
select * from (select gene, count(distinct patient_id) as patient_count, 'somatic' as type from var_genes where type='somatic' group by gene order by patient_count desc ) s where rownum <= 20;
end
my $var_top20_mysql = <<'END';
(select * from (select gene, count(distinct patient_id) as patient_count, 'germline' as type from var_genes where type='germline' and gene is not null group by gene order by patient_count desc ) g limit 20) union
(select * from (select gene, count(distinct patient_id) as patient_count, 'somatic' as type from var_genes where type='somatic' and gene is not null group by gene order by patient_count desc ) s limit 20);
END
my $var_samples_tmp = <<'end';
select v.*,c.genome_version from processed_cases c, var_samples v left join var_sample_avia_oc a on (
v.patient_id=a.patient_id and v.case_id=a.case_id and v.sample_id=a.sample_id and v.type=a.type and v.chromosome=a.chromosome and v.start_pos=a.start_pos and v.end_pos=a.end_pos and v.ref=a.ref and v.alt=a.alt )
where v.patient_id=c.patient_id and v.case_id=c.case_id and a.patient_id is null
end
my $project_fusion = <<'END';
select left_chr, left_gene, right_chr, right_gene, substr(var_level,1,1) as var_level, project_id,count(distinct v.patient_id) as count from var_fusion v, project_cases p 
where v.patient_id=p.patient_id and v.case_id=p.case_id group by project_id,left_chr,left_gene,right_chr,right_gene,substr(var_level,1,1);
END
my $project_diagnosis_fusion = <<'END';
select left_chr, left_gene, right_chr, right_gene, substr(var_level,1,1) as var_level, project_id,diagnosis,count(distinct v.patient_id) as count from var_fusion v, project_cases p, patients p2 
where v.patient_id=p.patient_id and v.case_id=p.case_id and v.patient_id=p2.patient_id group by project_id,left_chr,left_gene,right_chr,right_gene,substr(var_level,1,1),diagnosis
END

my $var_sample_avia_oc_hg19 = <<'end';
select v.*,a.* 
from var_samples_tmp v, hg19_annot_oc a
where
v.genome_version='hg19' and
v.chromosome = a.chr and 
v.start_pos=query_start and 
v.end_pos=query_end and 
v.ref=allele1 and 
v.alt=allele2
end
my $var_sample_avia_oc_hg38 = <<'end';
select v.*,a.* 
from var_samples_tmp v, hg38_annot_oc a
where
v.genome_version='hg38' and
v.chromosome = a.chr and 
v.start_pos=query_start and 
v.end_pos=query_end and 
v.ref=allele1 and 
v.alt=allele2
end
my $var_sample_avia_oc_hg19_full = <<'end';
select v.*,c.genome_version,a.* 
from var_samples v, hg19_annot_oc a, processed_cases c
where
v.patient_id=c.patient_id and
v.case_id=c.case_id and
c.genome_version='hg19' and
v.chromosome = a.chr and 
v.start_pos=query_start and 
v.end_pos=query_end and 
v.ref=allele1 and 
v.alt=allele2
end
my $var_sample_avia_oc_hg38_full = <<'end';
select v.*,c.genome_version,a.* 
from var_samples v, hg38_annot_oc a, processed_cases c
where
v.patient_id=c.patient_id and
v.case_id=c.case_id and
c.genome_version='hg38' and
v.chromosome = a.chr and 
v.start_pos=query_start and 
v.end_pos=query_end and 
v.ref=allele1 and 
v.alt=allele2
end

my %var_cnv_genes_indexes = ( "var_cnv_genes_idx" => "patient_id, case_id, sample_id, start_pos, end_pos" );
my %var_cnvkit_genes_indexes = ( "var_cnvkit_genes_idx" => "patient_id, case_id, sample_id, start_pos, end_pos" );
my %var_diagnosis_aa_cohort_indexes = ( "var_diagnosis_aa_cohort_idx" => "project_id, diagnosis, gene, type" );
my %var_diagnosis_gene_cohort_indexes = ( "var_diagnosis_gene_cohort_idx" => "project_id, diagnosis, gene, type" );
my %var_aa_cohort_oc_indexes = ( "var_aa_cohort_oc_idx" => "project_id, gene, type" );
my %var_gene_cohort_indexes = ( "var_gene_cohort_idx" => "project_id, gene, type" );
my %var_gene_tier_indexes = ( "var_gene_tier_patient" => "patient_id" );
my %var_genes_indexes = ( "var_genes_gene" => "gene" );

my %var_sample_avia_oc_indexes = ( "var_samle_avia_oc_coord" => "chromosome, start_pos, end_pos, ref, alt",
"var_sample_avia_oc_gene" => "type, gene,canonicalprotpos",
"var_sample_avia_oc_patient" =>  "type, patient_id, case_id, sample_id",
"var_sample_avia_oc_pk" =>  "type, patient_id, case_id, sample_id, chromosome, start_pos, end_pos, ref, alt",
"var_sample_avia_oc_sample" => "sample_id" );

#print "$cases\n$fusion_count\n$processed_sample_cases\n";

if (!$refresh_all && !$do_cnv && !$do_prj_summary && !$do_avia && !$do_avia_full && !$do_cohort) {
    die "please specifiy options!\n$usage";
}

my $dbh = getDBI();
my $db_type = getDBType();
my $sid = getDBSID();
my $host = getDBHost();


if ($refresh_all || $do_prj_summary) {
  print_log("Refrshing project views...on $sid");
  do_insert('project_patients',$project_patients, 1);
  do_insert('project_samples', $project_samples, 1);
  do_insert('cases', $cases, 1);
  do_insert('var_cases', $var_cases, 1);
  do_insert('sample_cases', $sample_cases, 1);
  do_insert('project_cases', $project_cases, 1);  
  do_insert('processed_sample_cases', $processed_sample_cases, 1);
  do_insert('project_processed_cases', $project_processed_cases, 1);  
  do_insert('project_patient_summary', $project_patient_summary, 1);
  do_insert('project_sample_summary', $project_sample_summary, 1);
  do_insert('user_projects', $user_projects, 1);
  do_insert('fusion_count', $fusion_count, 1);  
  do_insert('project_mview', $project_mview, 1);
}

if ($refresh_all || $do_avia) {
  print_log("Refrshing AVIA view...");
  do_insert('var_samples_tmp', $var_samples_tmp,1);
  do_insert('var_sample_avia_oc', $var_sample_avia_oc_hg19);
  do_insert('var_sample_avia_oc', $var_sample_avia_oc_hg38);
}

if ($do_avia_full) {
  print_log("Refrshing full AVIA view...");
  do_create('var_sample_avia_oc', $var_sample_avia_oc_hg19_full);
  do_insert('var_sample_avia_oc', $var_sample_avia_oc_hg38_full, 0, \%var_sample_avia_oc_indexes);
}

if ((1==2) && ($refresh_all || $do_cnv)) {
  print_log("Refrshing CNV views...on $sid");
  do_create('var_cnv_genes', $var_cnv_genes_hg19, );
  do_insert('var_cnv_genes', $var_cnv_genes_hg38, 0, \%var_cnv_genes_indexes);
  do_create('var_cnvkit_genes', $var_cnvkit_genes_hg19, );
  do_insert('var_cnvkit_genes', $var_cnvkit_genes_hg38, 0, \%var_cnvkit_genes_indexes);
}

if ($refresh_all || $do_cohort) {
  print_log("Refrshing cohort views...on $sid");    
  do_create('var_aa_cohort_oc', $var_aa_cohort_oc, \%var_aa_cohort_oc_indexes);
  do_create('var_genes', $var_genes, \%var_genes_indexes);
  do_insert('var_count', $var_count, 1);
  do_create('var_diagnosis_aa_cohort', $var_diagnosis_aa_cohort, \%var_diagnosis_aa_cohort_indexes);
  do_create('var_diagnosis_gene_cohort', $var_diagnosis_gene_cohort, \%var_diagnosis_gene_cohort_indexes);
  do_create('var_gene_cohort', $var_gene_cohort, \%var_gene_cohort_indexes);
  do_create('var_gene_tier', $var_gene_tier, \%var_gene_tier_indexes);  
  do_insert('project_diagnosis_gene_tier', $project_diagnosis_gene_tier, 1);
  do_insert('project_gene_tier',$project_gene_tier, 1);
  do_insert('var_tier_avia_count', $var_tier_avia_count, 1);
  if ($db_type eq "oracle") {
    do_insert('var_top20', $var_top20, 1);
  }
  if ($db_type eq "mysql") {
    do_insert('var_top20', $var_top20_mysql, 1);
  }
  do_insert('project_fusion', $project_fusion, 1);
  do_insert('project_diagnosis_fusion', $project_diagnosis_fusion, 1);
=======
	print_log("Refrshing cohort views...on $sid");	
  do_create('VAR_AA_COHORT_OC', $VAR_AA_COHORT_OC, \%VAR_AA_COHORT_OC_INDEXES);
	do_create('VAR_GENES', $VAR_GENES, \%VAR_GENES_INDEXES);
	do_insert('VAR_COUNT', $VAR_COUNT, 1);
	do_create('VAR_DIAGNOSIS_AA_COHORT', $VAR_DIAGNOSIS_AA_COHORT, \%VAR_DIAGNOSIS_AA_COHORT_INDEXES);
	do_create('VAR_DIAGNOSIS_GENE_COHORT', $VAR_DIAGNOSIS_GENE_COHORT, \%VAR_DIAGNOSIS_GENE_COHORT_INDEXES);
	do_create('VAR_GENE_COHORT', $VAR_GENE_COHORT, \%VAR_GENE_COHORT_INDEXES);
	do_create('VAR_GENE_TIER', $VAR_GENE_TIER, \%VAR_GENE_TIER_INDEXES);	
	do_insert('PROJECT_DIAGNOSIS_GENE_TIER', $PROJECT_DIAGNOSIS_GENE_TIER, 1);
	do_insert('PROJECT_GENE_TIER',$PROJECT_GENE_TIER, 1);
	do_insert('VAR_TIER_AVIA_COUNT', $VAR_TIER_AVIA_COUNT, 1);
	do_insert('VAR_TOP20', $VAR_TOP20, 1);
  do_insert('PROJECT_FUSION', $PROJECT_FUSION, 1);
  do_insert('PROJECT_DIAGNOSIS_FUSION', $PROJECT_DIAGNOSIS_FUSION, 1);
	
>>>>>>> 54c74714cbdd507882ad9921a7ec0204c8bbe10d
}

#do_insert('var_patient_annotation',0);
$dbh->disconnect();
print_log("Done updating on $host ($sid)");

sub print_log {
    my ($msg) = @_;
    #open cmd_file, ">>$cmd_log_file" || print_log("cannot create command log file";
    #print cmd_file "[".localtime->strftime('%y-%m-%d %h:%m:%s')."] $msg");
    #close(cmd_file);
    $msg = "[".localtime->strftime('%y-%m-%d %h:%m:%s')."] $msg\n";
    print $msg;
}

sub do_insert {
  my ($table_name, $sql, $truncate, $indexes_ref) = @_;
  my %indexes = ();
  if ($indexes_ref) {
    %indexes = %{$indexes_ref};
  }
  print_log("table: $table_name");  
  $sql =~ s/\n/ /g;
  $sql =~ s/;//g;
  if ($show_sql) {
    print_log("sql: $sql");
  }
  if ($truncate) {
    $dbh->do("truncate table $table_name");
    $dbh->commit(); 
    foreach my $index_name (keys %indexes){
      my $columns = $indexes{$index_name};
      if ($db_type eq "oracle") {
        $dbh->do("drop index $index_name");
      }
      if ($db_type eq "mysql") {
        $dbh->do("drop index $index_name on $table_name");
      }
    }
  }
  $dbh->do("insert into $table_name $sql");
  $dbh->commit(); 
  foreach my $index_name (keys %indexes){
    my $columns = $indexes{$index_name};
    $dbh->do("create index $index_name on $table_name ($columns)");
  }
}

sub do_create {
  my ($table_name, $sql, $indexes_ref) = @_;
  my %indexes = ();
  if ($indexes_ref) {
    %indexes = %{$indexes_ref};
  }
  print_log("table: $table_name");
  $sql =~ s/\n/ /g;
  $sql =~ s/;//g;
  if ($show_sql) {
    print_log("sql: $sql");
  }
  if ($db_type eq "oracle") {
    $dbh->do("begin execute immediate 'drop table $table_name'; exception when others then if sqlcode != -942 then raise;end if;end;");
  }
  if ($db_type eq "mysql") {
    $dbh->do("drop table if exists $table_name");
  }
  $dbh->do("create table $table_name as $sql");
  foreach my $index_name (keys %indexes){
    my $columns = $indexes{$index_name};
    $dbh->do("create index $index_name on $table_name ($columns)");
  }
}



