Args<-commandArgs()
in_file<-Args[6]
gene_stat_file<-Args[7]

data<-read.table(in_file, header=T, com='', sep="\t")

d<-data[,4:length(data)]
mat<-as.matrix(d) # convert to matrix
mat<-t(mat)

colnames(mat)<-data[,3]
mat <- log2(mat+1)
sd_gene <- apply(mat, 2, sd)
mat <- mat[,which(sd_gene!=0)]
mean_gene <- apply(mat, 2, mean)
median_gene <- apply(mat, 2, median)
sd_gene <- sd_gene[which(sd_gene!=0)]
#scaled_mat <- (mat - median_gene)/sd_gene
#scaled_mat <- mat - median_gene
#scaled_mat <- mat

gene_stat <- cbind(as.matrix(mean_gene),as.matrix(sd_gene),as.matrix(median_gene))
colnames(gene_stat)<-c("mean","sd","median")
write.table(gene_stat, file=gene_stat_file, sep='\t', col.names=TRUE);
#write.table(scaled_mat, file=gene_stat_file, sep='\t', col.names=FALSE);


