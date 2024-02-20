Args<-commandArgs()
n1=as.numeric(unlist(strsplit(Args[6], ",")))
n2=as.numeric(unlist(strsplit(Args[7], ",")))
t<-cor.test(n1,n2)
g<-cor.test(n1,n2,alternative="g")
l<-cor.test(n1,n2,alternative="l")
cat(paste(t$p.value, g$p.value, l$p.value))


