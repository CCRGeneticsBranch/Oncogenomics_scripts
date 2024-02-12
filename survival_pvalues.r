library(survival)
options(warn=-1)
Args<-commandArgs()
in_file<-Args[6]
out_file<-Args[7]
out_summary<-Args[8]


data<-read.table(in_file, header=T, com='', sep="\t")
data$Time <- as.numeric(as.character(data$Time))
s<-Surv(data$Time, data$Status == 1)
sorted_exp <- sort(data$Exp)
#cutoffs <- unique(round(sorted_exp, 2))
cutoffs <- unique(round(sorted_exp[ceiling(length(sorted_exp)/10):floor(length(sorted_exp)/10*9)], 2))
print(cutoffs)
if (length(cutoffs) == 1) {
	cat('only one group',file=out_summary)	
} else {
	min_pvalue <- 100;
	min_cutoff <- 0;
	pvalue <- vector(, length(cutoffs))
	for (n in 1:length(cutoffs))
	{
		res <- tryCatch({
			diff <- survdiff(s~(data$Exp > cutoffs[n]))
			pvalue[n] <- 1 - pchisq(diff$chisq, length(diff$n) - 1)
			if (pvalue[n] < min_pvalue) {
				min_pvalue <- pvalue[n]
				min_cutoff <- cutoffs[n]
			}
		}, error= function(e){
			print(e)
		})
	}

	df = data.frame(cutoffs, pvalue)
	df = df[order(df[,2]),]
	write.table(df, file=out_file, sep='\t', col.names=FALSE, row.names=FALSE);

	med <- median(sorted_exp)
	print(med)
	diff <- survdiff(s~(data$Exp > med))
	med_pvalue <- 1 - pchisq(diff$chisq, length(diff$n) - 1)
	cat(med,med_pvalue,min_cutoff,min_pvalue,file=out_summary)
}

