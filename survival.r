library(survival)

Args<-commandArgs()
in_file<-Args[6]

data<-read.table(in_file, header=T, com='', sep="\t")
s<-Surv(data$Time, data$Status == 1)
sorted_exp <- sort(data$Exp)
cutoffs <- unique(round(sorted_exp[ceiling(length(sorted_exp)/10):floor(length(sorted_exp)/10*9)], 1))

min_pvalue <- 100;
min_cutoff <- 0;
pvalue <- vector(, length(cutoffs))
for (n in 1:length(cutoffs))
{
	diff <- survdiff(s~(data$Exp > cutoffs[n]))
	pvalue[n] <- 1 - pchisq(diff$chisq, length(diff$n) - 2)
	if (pvalue[n] < min_pvalue) {
		min_pvalue <- pvalue[n]
		min_cutoff <- cutoffs[n]
	}
}

km_all <- survfit(s~1)
km_median <- survfit(s~(data$Exp > median(data$Exp)))
km_min <- survfit(s~(data$Exp > min_cutoff))

diff_median <- survdiff(s~(data$Exp > median(data$Exp)))
pvalue_median <- 1 - pchisq(diff$chisq, length(diff$n) - 1)

png('survival_median.png')
plot(km_median, xlab="Time ( Days )",ylab="Probability of survival")
title(main=paste("Exp-cutoff =  ", round(median(data$Exp),2), " ; p-value = ",  round(pvalue_median,3)))
#plot(km_all)
dev.off()
png('survival_min.png')
plot(km_min, xlab="Time ( Days )",ylab="Probability of survival")
title(main=paste("Exp-cutoff =  ", round(min_cutoff,2), " ; p-value = ",  round(min_pvalue,3)))
dev.off()

df = data.frame(cutoffs, pvalue)
write.table(df, file='out.tsv', sep='\t', col.names=FALSE);


