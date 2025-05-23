suppressMessages(library(survival))
suppressMessages(library(dplyr))
options(warn=-1)

calPvalues <- function(d, s) {
	sorted_exp <- sort(d)
	cutoffs <- unique(round(sorted_exp[ceiling(length(sorted_exp)/10):floor(length(sorted_exp)/10*9)], 8))
	if (length(cutoffs) == 1) {
		return(NA);
	}
	min_pvalue <- 100;
	min_chisq <- 0;
	min_cutoff <- 0;
	min_better_group <- "NA";
	pvalue <- vector(, length(cutoffs))
	for (n in 1:length(cutoffs))
	{
		res <- tryCatch({
			diff <- survdiff(s~(d > cutoffs[n]))
			pvalue[n] <- 1 - pchisq(diff$chisq, length(diff$n) - 1)
			if (pvalue[n] < min_pvalue) {
				min_pvalue <- pvalue[n]
				min_cutoff <- cutoffs[n]
				min_chisq <- round(diff$chisq,4)
				min_better_group <- "Low";
				if (grepl("TRUE", names(diff$n)[diff$obs/diff$exp==min(diff$obs/diff$exp)]))
					min_better_group <- "High";

			}
		}, error= function(e){
			return(NA);
		})
	}

	#df = data.frame(cutoffs, pvalue)
	#df = df[order(df[,2]),]
	#write.table(df, file=out_file, sep='\t', col.names=FALSE, row.names=FALSE);

	med <- median(sorted_exp)
	diff <- survdiff(s~(d > med))
	med_pvalue <- 1 - pchisq(diff$chisq, length(diff$n) - 1)
	med_chisq <- round(diff$chisq,4)
	med_better_group <- "Low";
	if (grepl("TRUE", names(diff$n)[diff$obs/diff$exp==min(diff$obs/diff$exp)]))
		med_better_group <- "High";
	return (c(round(log2(med+1),4),med_chisq,med_better_group,round(med_pvalue,4),round(log2(min_cutoff+1),4),min_chisq,min_better_group,round(min_pvalue,4)))
}


Args<-commandArgs(trailingOnly=T)
survival_file<-Args[1]
expression_file<-Args[2]
out_file<-Args[3]

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
#df_exp <- df_exp[1:20,]
df_exp <- as.data.frame(t(df_exp))
df_exp$SampleID <- rownames(df_exp)
df_surv$SampleID <- as.character(df_surv$SampleID);
data <- df_surv %>% dplyr::inner_join(df_exp, by=c("SampleID"="SampleID"))

data$Time <- as.numeric(as.character(data$Time))
s<-Surv(data$Time, data$Status == 1)
d <- data[,5:ncol(data)]
pvalues <- lapply(d, calPvalues, s)
pvalues <- as.data.frame(t(as.data.frame(pvalues)))
colnames(pvalues) <- c("median","median_chisq","median_better_group","median_pvalue","min_cutoff","min_chisq","min_better_group","min_pvalue")
pvalues$FDR <- round(p.adjust(pvalues$min_pvalue, method="fdr"),4)
write.table(pvalues, out_file, col.names=NA, row.names=T, sep="\t", quote=F)

