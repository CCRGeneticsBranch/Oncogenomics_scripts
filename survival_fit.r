library(survival)
options(warn=-1)

Args<-commandArgs(trailingOnly=T)
in_file<-Args[1]
out_textfile<-Args[2]
out_summary<-Args[3]

data<-read.table(in_file, header=T, com='', sep="\t")
data$Time <- as.numeric(as.character(data$Time))
s<-Surv(data$Time, data$Status == 1)
km <- survfit(s~(data$Value), conf.type = "log-log")
sm = summary(km, censored=T)
m <- cbind(sm$time, sm$surv, gsub("data\\$Value=", "", as.character(sm$strata)), sm$n.event, sm$n.censor)
values = unique(data$Value)
if (length(values) == 1)
	m[,3] <- as.character(values[1])
#summary(km)$n.censor
write.table(m, out_textfile, sep="\t", row.names=FALSE, col.names=FALSE, quote=F)

sink(out_summary)
res <- tryCatch({
			diff <- survdiff(s~(data$Value))
			pvalue <- 1 - pchisq(diff$chisq, length(diff$n) - 1)
			cat(paste("pvalue", pvalue, sep="\t"))
			cat("\n")
		}, error= function(e){
			cat(paste("pvalue", "NA", sep="\t"))
			cat("\n")
		})

for (i in values) {
	cat(paste(i,length(which(data$Value==i)), sep="\t"))
	cat("\n")
}
sink()
#svg(out_file)
#plot(km, xlab="Time ( Days )",ylab="Probability of survival",lty = 1:1,lwd=3:3, col=c("red","blue"))
#group = c(paste("High (", hight_num, ")"), paste("Low (", low_num, ")"))
#legend("topright", legend=unique(group), col=c("red","blue"), lty = 1:1,lwd=3:3, horiz=FALSE, bty='n')
#title(main=paste("Exp-cutoff =  ", cutoff, " ; p-value = ",  pvalue))
#dev.off()


