suppressMessages(library(survival))
suppressMessages(library(dplyr))
options(warn=-1)

calPvalues <- function(d, s) {
	sorted_exp <- sort(d)
	cutoffs <- unique(round(sorted_exp[ceiling(length(sorted_exp)/10):floor(length(sorted_exp)/10*9)], 2))
	if (length(cutoffs) == 1) {
		return(NA);
	}
	min_pvalue <- 100;
	min_cutoff <- 0;
	pvalue <- vector(, length(cutoffs))
	for (n in 1:length(cutoffs))
	{
		res <- tryCatch({
			diff <- survdiff(s~(d > cutoffs[n]))
			pvalue[n] <- 1 - pchisq(diff$chisq, length(diff$n) - 1)
			if (pvalue[n] < min_pvalue) {
				min_pvalue <- pvalue[n]
				min_cutoff <- cutoffs[n]
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
	return (c(round(log2(med+1),2),round(med_pvalue,4),round(log2(min_cutoff+1),2),round(min_pvalue,4)))
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
df_exp <- as.data.frame(t(df_exp))
df_exp$SampleID <- rownames(df_exp)
data <- df_surv %>% dplyr::inner_join(df_exp, by=c("SampleID"="SampleID"))

data$Time <- as.numeric(as.character(data$Time))
s<-Surv(data$Time, data$Status == 1)
data <- data[,5:ncol(data)]
pvalues <- lapply(data, calPvalues, s)
pvalues <- as.data.frame(t(as.data.frame(pvalues)))
colnames(pvalues) <- c("median","median_pvalue","min_cutoff","min_pvalue")
pvalues$FDR <- round(p.adjust(pvalues$min_pvalue, method="fdr"),4)
write.table(pvalues, out_file, col.names=NA, row.names=T, sep="\t", quote=F)

