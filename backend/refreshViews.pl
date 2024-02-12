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
my $do_cohort = 0;
my $show_sql = 0;

my $usage = <<__EOUSAGE__;

Usage:

$0 [options]

Options:

  -a            Refresh all
  -c            Refresh CNV views
  -p            Refresh Project views
  -v            Refresh AVIA views
  -h            Refresh Cohort views
  -s            Show SQL statement
  
__EOUSAGE__



GetOptions (
  'a' => \$refresh_all,
  'c' => \$do_cnv,
  'p' => \$do_prj_summary,
  'v' => \$do_avia,
  'h' => \$do_cohort,
  's' => \$show_sql
);

my $CASES = <<'END';
select distinct c.*,s.case_name from sample_case_mapping s,processed_cases c where s.patient_id=c.patient_id and s.case_id=c.case_id;
END
my $FUSION_COUNT = <<'END';
select s.patient_id, s.case_name, s.case_id, count(*) as fusion_cnt from var_fusion v, sample_cases s where v.patient_id=s.patient_id and v.sample_id=s.sample_id group by s.patient_id, s.case_name, s.case_id;
END
my $PROCESSED_SAMPLE_CASES = <<'END';
select distinct s.patient_id,s.sample_id, c.case_name,c.case_id, c.path, s.sample_name, s.sample_alias, s.exp_type, s.tissue_cat, v.type,count(*) as var_cnt 
from samples s, cases c, var_samples v
where s.sample_id=v.sample_id and v.patient_id=c.patient_id and v.case_id=c.case_id
group by s.patient_id,s.sample_id, c.case_name,c.case_id, c.path, s.sample_name, s.sample_alias, v.type,s.exp_type, s.tissue_cat;
END
my $PROJECT_CASES = <<'END';
select distinct p.project_id,p.patient_id,s.case_name,s.case_id from project_samples p, sample_cases s where p.sample_id=s.sample_id and 
  not exists(select * from project_case_blacklist b where p.name=b.project and s.patient_id=b.patient_id and s.case_name=b.case_name);
END
my $PROJECT_DIAGNOSIS_GENE_TIER = <<'END';
select project_id, diagnosis, gene,type,'germline' as tier_type, germline_level  as tier, count(patient_id) as cnt from (select distinct p.project_id, p2.diagnosis, v.gene, v.type, p.patient_id, v.germline_level from var_gene_tier v, project_patients p, patients p2
  where p.patient_id=p2.patient_id and p.patient_id=v.patient_id)
  group by project_id,diagnosis, gene,type,germline_level
  union
  select project_id, diagnosis, gene,type,'somatic' as tier_type, somatic_level as tier, count(patient_id) as cnt from (select distinct p.project_id, p2.diagnosis, v.gene, v.type, p.patient_id, v.somatic_level from var_gene_tier v, project_patients p, patients p2
  where p.patient_id=p2.patient_id and p.patient_id=v.patient_id)
  group by project_id,diagnosis, gene,type,somatic_level;
END
my $PROJECT_GENE_TIER = <<'END';
select project_id, gene,type,'germline' as tier,germline_level as tier_type, count(patient_id) as cnt from (select distinct p.project_id, v.gene, v.type, p.patient_id, v.germline_level from var_gene_tier v, project_patients p
  where p.patient_id=v.patient_id)
  group by project_id,gene,type,germline_level
  union
  select project_id, gene,type,'somatic' as tier,somatic_level as tier_type, count(patient_id) as cnt from (select distinct p.project_id, v.gene, v.type, p.patient_id, v.somatic_level from var_gene_tier v, project_patients p
  where p.patient_id=v.patient_id)
  group by project_id,gene,type,somatic_level;
END

my $PROJECT_MVIEW = <<'END';
select distinct "ID","NAME","DESCRIPTION","ISPUBLIC","PATIENTS","CASES","SAMPLES","PROCESSED_PATIENTS","PROCESSED_CASES","VERSION","SURVIVAL","EXOME","PANEL","RNASEQ","WHOLE_GENOME","STATUS","USER_ID","CREATED_BY","UPDATED_AT" from 
				(select p1.id, p1.name, p1.description, p1.ispublic, 
				  (select count(distinct patient_id) from project_cases s where p1.id=s.project_id) as patients,
                  (select count(distinct case_name) from project_cases s where p1.id=s.project_id) as cases,
                  (select count(distinct sample_id) from project_samples s where p1.id=s.project_id) as samples,
				  (select count(distinct patient_id) from project_processed_cases s where p1.id=s.project_id) as processed_patients,
                  (select count(distinct case_id) from project_processed_cases s where p1.id=s.project_id) as processed_cases,
                  version,
				  (select count(distinct c1.patient_id) from project_patients c1, patient_details c2 where p1.id=c1.project_id and c1.patient_id=c2.patient_id and class='overall_survival') as Survival,
				  (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='Exome') as Exome,
				  (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='Panel') as Panel,
				  (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='RNAseq') as RNAseq,
				  (select count(distinct sample_id) from project_samples c1 where c1.project_id=p1.id and c1.exp_type='Whole Genome') as Whole_Genome,
				  status, p1.user_id, u.email as created_by, to_char(p1.updated_at, 'YYYY/MM/DD') as Updated_at
					 from projects p1 left join users u on p1.user_id=u.id,project_samples p2 where p1.id=p2.project_id) projects where (RNAseq is not null or Whole_Genome is not null or Exome is not null or Panel is not null or Panel is not null or Whole_Genome is not null);
END
my $PROJECT_PATIENT_SUMMARY = <<'END';
select p.project_id, name, count(distinct p.patient_id) as patients from project_patients p, var_samples s where p.patient_id=s.patient_id group by p.project_id, name;
END
my $PROJECT_PATIENTS = <<'END';
SELECT DISTINCT P.*,PROJECT_ID,NAME FROM PATIENTS P, SAMPLES S1, PROJECT_SAMPLE_MAPPING S2,PROJECTS J WHERE J.ID=S2.PROJECT_ID AND S1.SAMPLE_ID=S2.SAMPLE_ID AND S1.PATIENT_ID=P.PATIENT_ID;
END
my $PROJECT_PROCESSED_CASES = <<'END';
select distinct p.project_id,p.patient_id,p.case_name,c.case_id,c.path,c.version,c.genome_version from project_cases p, processed_cases c 
where p.patient_id=c.patient_id and p.case_id=c.case_id;
END
my $PROJECT_SAMPLE_SUMMARY = <<'END';
select project_id, count(distinct s.sample_id) as samples, exp_type from project_patients p, var_samples s where p.patient_id=s.patient_id group by project_id,exp_type;
END
my $PROJECT_SAMPLES = <<'END';
SELECT DISTINCT S1.*,PROJECT_ID,NAME,DIAGNOSIS FROM SAMPLES S1, PROJECT_SAMPLE_MAPPING S2,PROJECTS J,PATIENTS P WHERE J.ID=S2.PROJECT_ID AND S1.SAMPLE_ID=S2.SAMPLE_ID and S1.PATIENT_ID=P.PATIENT_ID;
END
my $SAMPLE_CASES = <<'END';
SELECT DISTINCT S.*,M.CASE_NAME,C.CASE_ID,C.PATH FROM SAMPLES S,SAMPLE_CASE_MAPPING M LEFT JOIN CASES C ON M.PATIENT_ID=C.PATIENT_ID AND M.CASE_NAME=C.CASE_NAME WHERE M.SAMPLE_ID=S.SAMPLE_ID;
END
my $USER_PROJECTS = <<'END';
select distinct * from (
(select distinct p.id as project_id, p.name as project_name, g.user_id,p.ispublic from project_group_users g, projects p 
where p.project_group=g.project_group)
union
(select distinct p.id as project_id, p.name as project_name, u.id as user_id,p.ispublic from users u, users_groups g, projects p where (u.id=g.user_id and g.group_id=p.id) or p.ispublic=1)
union
(select  p.id as project_id, p.name as project_name, u.user_id as user_id,p.ispublic from users_permissions u, projects p where u.perm='_superadmin')
);
END
my $VAR_CASES = <<'END';
  select distinct v.*,c.path,c.case_name from var_type v,cases c where v.patient_id=c.patient_id and v.case_id=c.case_id;
END
my $VAR_CNV_GENES_HG19 = <<'END';
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
END
my $VAR_CNV_GENES_HG38 = <<'END';
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
END
my $VAR_CNVKIT_GENES_HG19 = <<'END';
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
END
my $VAR_CNVKIT_GENES_HG38 = <<'END';
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
END
my $VAR_COUNT = <<'END';
  select chromosome, start_pos, end_pos, type, count(distinct patient_id) as patient_count from var_samples where type = 'germline' or type = 'somatic' group by chromosome, start_pos, end_pos, type;
END
my $VAR_AA_COHORT_OC = <<'END';
select project_id, gene, aa_site, type,count(patient_id) as cnt from (select distinct project_id, p2.patient_id,
  gene, CANONICALPROTPOS as aa_site, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id)
  group by project_id, gene, aa_site, type;
END
my $VAR_DIAGNOSIS_AA_COHORT = <<'END';
select project_id, diagnosis, gene, aa_site, type,count(patient_id) as cnt from (select distinct project_id, p2.diagnosis, p2.patient_id,
  gene, CANONICALPROTPOS as aa_site, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id)
  group by project_id, diagnosis, gene, aa_site, type;
END
my $VAR_DIAGNOSIS_GENE_COHORT = <<'END';
select project_id, diagnosis, gene, type,count(patient_id) as cnt from (select distinct project_id, p2.diagnosis, p2.patient_id,
  gene, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id)
  group by project_id, diagnosis, gene, type;
END
my $VAR_GENE_COHORT = <<'END';
select project_id, gene, type,count(patient_id) as cnt from (select distinct project_id, p2.patient_id,
  gene, p1.type from var_sample_avia_oc p1, project_patients p2 where
  p1.patient_id=p2.patient_id)
  group by project_id, gene, type;

END
my $VAR_GENE_TIER = <<'END';
select distinct p1.patient_id, p1.type, p1.gene, canonicalprotpos, germline_level, somatic_level from var_tier_avia p1,
  var_sample_avia_oc a where
  p1.chromosome=a.chromosome and
  p1.start_pos=a.start_pos and
  p1.end_pos=a.end_pos and
  p1.ref=a.ref and
  p1.alt=a.alt and p1.gene is not null;
END
my $VAR_GENES = <<'END';
select distinct s.patient_id, s.sample_id, s.exp_type, s.tissue_cat, s.normal_sample, s.rnaseq_sample, a.gene, a.type
from samples s,var_sample_avia_oc a
where
s.sample_id=a.sample_id;
END
my $VAR_TIER_AVIA_COUNT = <<'END';
select patient_id,case_id,sample_id,type,germline_level,somatic_level,count(*) as cnt from var_tier_avia group by patient_id,case_id,sample_id,type,germline_level,somatic_level;
END
my $VAR_TOP20 = <<'END';
select * from (select gene, count(distinct patient_id) as patient_count, 'germline' as type from var_genes where type='germline' group by gene order by patient_count desc ) where rownum <= 20 union
select * from (select gene, count(distinct patient_id) as patient_count, 'somatic' as type from var_genes where type='somatic' group by gene order by patient_count desc ) where rownum <= 20;
END
my $VAR_SAMPLE_AVIA_OC_HG19 = <<'END';
select v.*,c.genome_version,a.* 
from var_samples v, hg19_annot_oc a, cases c
where
v.patient_id=c.patient_id and
v.case_id=c.case_id and
c.genome_version='hg19' and
v.chromosome = a.chr and 
v.start_pos=query_start and 
v.end_pos=query_end and 
v.ref=allele1 and 
v.alt=allele2
END
my $VAR_SAMPLE_AVIA_OC_HG38 = <<'END';
select v.*,c.genome_version,a.* 
from var_samples v, hg38_annot_oc a, cases c
where
v.patient_id=c.patient_id and
v.case_id=c.case_id and
c.genome_version='hg38' and
v.chromosome = a.chr and 
v.start_pos=query_start and 
v.end_pos=query_end and 
v.ref=allele1 and 
v.alt=allele2
END

my %VAR_CNV_GENES_INDEXES = ( "VAR_CNV_GENES_IDX" => "PATIENT_ID, CASE_ID, SAMPLE_ID, START_POS, END_POS" );
my %VAR_CNVKIT_GENES_INDEXES = ( "VAR_CNVKIT_GENES_IDX" => "PATIENT_ID, CASE_ID, SAMPLE_ID, START_POS, END_POS" );
my %VAR_DIAGNOSIS_AA_COHORT_INDEXES = ( "VAR_DIAGNOSIS_AA_COHORT_IDX" => "PROJECT_ID, DIAGNOSIS, GENE, TYPE" );
my %VAR_DIAGNOSIS_GENE_COHORT_INDEXES = ( "VAR_DIAGNOSIS_GENE_COHORT_IDX" => "PROJECT_ID, DIAGNOSIS, GENE, TYPE" );
my %VAR_AA_COHORT_OC_INDEXES = ( "VAR_AA_COHORT_OC_IDX" => "PROJECT_ID, GENE, TYPE" );
my %VAR_GENE_COHORT_INDEXES = ( "VAR_GENE_COHORT_IDX" => "PROJECT_ID, GENE, TYPE" );
my %VAR_GENE_TIER_INDEXES = ( "VAR_GENE_TIER_PATIENT" => "PATIENT_ID" );
my %VAR_GENES_INDEXES = ( "VAR_GENES_GENE" => "GENE" );

my %VAR_SAMPLE_AVIA_OC_INDEXES = ( "VAR_SAMLE_AVIA_OC_COORD" => "CHROMOSOME, START_POS, END_POS, REF, ALT",
"VAR_SAMPLE_AVIA_OC_GENE" => "TYPE, GENE,CANONICALPROTPOS",
"VAR_SAMPLE_AVIA_OC_PATIENT" =>  "TYPE, PATIENT_ID, CASE_ID, SAMPLE_ID",
"VAR_SAMPLE_AVIA_OC_SAMPLE" => "SAMPLE_ID" );

#print "$CASES\n$FUSION_COUNT\n$PROCESSED_SAMPLE_CASES\n";

if (!$refresh_all && !$do_cnv && !$do_prj_summary && !$do_avia && !$do_cohort) {
    die "Please specifiy options!\n$usage";
}

my $dbh = getDBI();
my $sid = getDBSID();
my $host = getDBHost();


if ($refresh_all || $do_prj_summary) {
	print_log("Refrshing project views...on $sid");
	do_insert('PROJECT_PATIENTS',$PROJECT_PATIENTS, 1);
	do_insert('PROJECT_SAMPLES', $PROJECT_SAMPLES, 1);
	do_insert('CASES', $CASES, 1);
	do_insert('VAR_CASES', $VAR_CASES, 1);
	do_insert('SAMPLE_CASES', $SAMPLE_CASES, 1);
	do_insert('PROJECT_CASES', $PROJECT_CASES, 1);	
	do_insert('PROCESSED_SAMPLE_CASES', $PROCESSED_SAMPLE_CASES, 1);
	do_insert('PROJECT_PROCESSED_CASES', $PROJECT_PROCESSED_CASES, 1);	
	do_insert('PROJECT_PATIENT_SUMMARY', $PROJECT_PATIENT_SUMMARY, 1);
	do_insert('PROJECT_SAMPLE_SUMMARY', $PROJECT_SAMPLE_SUMMARY, 1);
	do_insert('USER_PROJECTS', $USER_PROJECTS, 1);
	do_insert('FUSION_COUNT', $FUSION_COUNT, 1);	
	do_insert('PROJECT_MVIEW', $PROJECT_MVIEW, 1);
}

if ($refresh_all || $do_avia) {
	print_log("Refrshing AVIA view...");
	do_create('VAR_SAMPLE_AVIA_OC', $VAR_SAMPLE_AVIA_OC_HG19);
	do_insert('VAR_SAMPLE_AVIA_OC', $VAR_SAMPLE_AVIA_OC_HG38, 0, \%VAR_SAMPLE_AVIA_OC_INDEXES);
}

if ($refresh_all || $do_cnv) {
	print_log("Refrshing CNV views...on $sid");
	do_create('VAR_CNV_GENES', $VAR_CNV_GENES_HG19, );
	do_insert('VAR_CNV_GENES', $VAR_CNV_GENES_HG38, 0, \%VAR_CNV_GENES_INDEXES);
	do_create('VAR_CNVKIT_GENES', $VAR_CNVKIT_GENES_HG19, );
	do_insert('VAR_CNVKIT_GENES', $VAR_CNVKIT_GENES_HG38, 0, \%VAR_CNVKIT_GENES_INDEXES);
}

if ($refresh_all || $do_cohort) {
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
	
}

#do_insert('VAR_PATIENT_ANNOTATION',0);
$dbh->disconnect();
print_log("done updating on $host ($sid)");

sub print_log {
    my ($msg) = @_;
    #open CMD_FILE, ">>$cmd_log_file" || print_log("cannot create command log file";
    #print CMD_FILE "[".localtime->strftime('%Y-%m-%d %H:%M:%S')."] $msg");
    #close(CMD_FILE);
    $msg = "[".localtime->strftime('%Y-%m-%d %H:%M:%S')."] $msg\n";
	  print $msg;
}

sub do_insert {
	my ($table_name, $sql, $truncate, $indexes_ref) = @_;
	my %indexes = ();
	if ($indexes_ref) {
  	%indexes = %{$indexes_ref};
  }
	print_log("Table: $table_name");	
	$sql =~ s/\n/ /g;
	$sql =~ s/;//g;
	if ($show_sql) {
		print_log("SQL: $sql");
	}
	if ($truncate) {
		$dbh->do("truncate table $table_name");
		$dbh->commit();	
		foreach my $index_name (keys %indexes){
			my $columns = $indexes{$index_name};
			$dbh->do("drop index $index_name");
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
	print_log("Table: $table_name");
	$sql =~ s/\n/ /g;
	$sql =~ s/;//g;
	if ($show_sql) {
		print_log("SQL: $sql");
	}
	$dbh->do("BEGIN EXECUTE IMMEDIATE 'drop table $table_name'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE;END IF;END;");
	$dbh->do("create table $table_name as $sql");
	foreach my $index_name (keys %indexes){
		my $columns = $indexes{$index_name};
		$dbh->do("create index $index_name on $table_name ($columns)");
	}
}



