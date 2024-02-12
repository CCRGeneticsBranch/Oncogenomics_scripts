library(survival)
options(warn=-1)

Args<-commandArgs()
in_file<-Args[6]
#out_file<-Args[7]
out_textfile<-Args[7]
cutoff<-as.numeric(Args[8])
#pvalue<-as.numeric(Args[10])

data<-read.table(in_file, header=T, com='', sep="\t")
data$Exp <- as.numeric(as.character(data$Exp))
data$Time <- as.numeric(as.character(data$Time))
data$strata = data$Exp <= cutoff
s<-Surv(data$Time, data$Status == 1)
km <- survfit(s~(data$strata), conf.type = "log-log")
sm = summary(km, censored=T)
m <- cbind(sm$time, sm$surv, sm$strata, sm$n.event, sm$n.censor)
#summary(km)$n.censor
write.table(m, out_textfile, sep="\t", row.names=FALSE, col.names=FALSE)
#svg(out_file)
#plot(km, xlab="Time ( Days )",ylab="Probability of survival",lty = 1:1,lwd=3:3, col=c("red","blue"))
hight_num = sum(data$Exp > cutoff)
low_num = sum(data$Exp <= cutoff)
cat(hight_num,low_num)
#group = c(paste("High (", hight_num, ")"), paste("Low (", low_num, ")"))
#legend("topright", legend=unique(group), col=c("red","blue"), lty = 1:1,lwd=3:3, horiz=FALSE, bty='n')
#title(main=paste("Exp-cutoff =  ", cutoff, " ; p-value = ",  pvalue))
#dev.off()


