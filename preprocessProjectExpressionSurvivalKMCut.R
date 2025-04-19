suppressMessages(library(kmcut))
suppressMessages(library(dplyr))
options(warn=-1)

Args<-commandArgs(trailingOnly=T)
survival_file<-Args[1]
expression_file<-Args[2]
basename<-Args[3]
run_perm<-Args[4]

#survival_file="/mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/storage/project_data/24601/survival/overvall_survival.tsv"
#expression_file="/mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/storage/project_data/24601/expression.tpm.tsv"
df_surv<-read.table(survival_file, header=T, com='', sep="\t")
df_exp<-read.table(expression_file, header=T, com='', sep="\t", check.names=F)

df_exp <- df_exp %>% dplyr::filter(gene_type == "protein_coding")
df_exp <- df_exp[,8:ncol(df_exp)]
df_exp$length=NULL
df_exp <- as.data.frame(df_exp %>% dplyr::group_by(gene_name) %>% dplyr::summarize_all(list(mean)))
rownames(df_exp) <- df_exp$gene_name
df_exp$gene_name <- NULL

cn <- intersect(df_surv$sample_id, colnames(df_exp))
#df_surv <- df_surv %>% dplyr::filter(sample_id %in% cn)
df_exp <- df_exp[, cn]
min_tpm <- 3
min_sample <- ncol(df_exp)/5
keep <- rowSums( df_exp >= min_tpm ) >= min_sample
df_exp <- df_exp[keep,]
out_df <- data.frame("tracking_id"=rownames(df_exp))
out_df <- cbind(out_df, df_exp)
d <- dirname(survival_file)
setwd(d)
out_exp_name <- paste0(d, "/expression.tpm.", basename, ".tsv");
write.table(out_df, out_exp_name, sep="\t", quote=F, row.names=F)
se = create_se_object(efile = out_exp_name, sfile = survival_file)
km_opt_scut(obj = se, bfname = basename, wpdf = FALSE, verbose = FALSE)
out_km <- paste0(basename, "_KMopt_minf_0.10.txt")
if (file.exists(out_km)) {
	df <- read.table(out_km, head=T, sep="\t")
	df$FDR_P <- round(p.adjust(df$P, method="fdr"),10)
	write.table(df, out_km, sep="\t", quote=F, row.names=F, col.names=T)
}
if (run_perm == "Y")
	km_opt_pcut(obj = se, bfname = basename, n_iter = 50, wlabels = TRUE, wpdf = FALSE, verbose = FALSE, nproc = 32)


