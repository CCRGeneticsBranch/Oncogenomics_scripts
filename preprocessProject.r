Args<-commandArgs(trailingOnly=T)
file_prefix<-Args[1]
lib_type<-Args[2]
norm_type<-Args[3]

print("read file...")
in_file<-paste(file_prefix, "-coding.", lib_type, ".", norm_type, ".tsv", sep="");
gene_stat_file<-paste(file_prefix, "-stat.", lib_type, ".", norm_type, ".tsv", sep="");
loading_file<-paste(file_prefix, "-loading.", lib_type, ".", norm_type, ".tsv", sep="");
coord_file<-paste(file_prefix, "-coord_tmp.", lib_type, ".", norm_type, ".tsv", sep="");
std_file<-paste(file_prefix, "-std.", lib_type, ".", norm_type, ".tsv", sep="");
z_loading_file<-paste(file_prefix, "-loading.", lib_type, ".", norm_type, ".zscore.tsv", sep="");
z_coord_file<-paste(file_prefix, "-coord_tmp.", lib_type, ".", norm_type, ".zscore.tsv", sep="");
z_std_file<-paste(file_prefix, "-std.", lib_type, ".", norm_type, ".zscore.tsv", sep="");
rds_file<-paste(file_prefix, "-coding.", lib_type, ".", norm_type, ".rds", sep="");
#in_file<-Args[6]
#gene_stat_file<-Args[7]
#loading_file<-Args[8]
#coord_file<-Args[9]
#std_file<-Args[10]
#rds_file<-Args[11]
data <- as.data.frame(data.table::fread(in_file, sep="\t", header = TRUE))
rownames(data) = data$V1
#data<-read.table(in_file, header=T, sep="\t")
print("calculating statistics...")
d<-data[2:nrow(data),2:ncol(data)]
if (!is.na(rds_file)) {
	print("save RDS...")
	saveRDS(d, rds_file)
}
#dim(d)
ncol(data)
if (ncol(data) < 3 ) {
	print("No samples. Exit...")
	quit()
}
#print("to matrix...")
#d<-data[,2:length(data)]
mat<-as.matrix(d) # convert to matrix
mat<-t(mat)
#colnames(mat)<-data[,1]
class(mat)<-"numeric"
#min(mat)
#print("to log2...")
#mat <- log2(mat+1)
neg <- mat[which(mat<0)]
#length(neg)
#summary(neg)
mat <- ifelse(mat < 0, 0, mat)
#print("sd...")
sd_gene <- apply(mat, 2, sd)
mat3000 <- mat[,which(sd_gene > sort(sd_gene, decreasing=T)[3000])]
#mat3000 <- mat
mat <- mat[,which(sd_gene!=0)]
#print("mean...")
mean_gene <- apply(mat, 2, mean)
#print("median...")
median_gene <- apply(mat, 2, median)
sd_gene <- sd_gene[which(sd_gene!=0)]
#scaled_mat <- t((t(mat) - mean_gene)/sd_gene)
#scaled_mat <- mat
gene_stat <- cbind(as.matrix(mean_gene),as.matrix(sd_gene),as.matrix(median_gene))
write.table(gene_stat, file=gene_stat_file, sep='\t', col.names=FALSE, quote=FALSE);
#write.table(scaled_mat, file=gene_stat_file, sep='\t', col.names=FALSE);
print("calculating PCA...")
if (!is.na(loading_file)) {
	res<-prcomp(mat3000)
	s <- min(30, ncol(res$rotation))
	if (s > 3) {
		write.table(res$rotation[,1:s], file=loading_file, sep='\t', col.names=FALSE, quote = FALSE);
		write.table(res$x[,1:3], file=coord_file, sep='\t', col.names=FALSE, quote = FALSE);
		write.table(res$sdev, file=std_file, sep='\t', col.names=FALSE, quote = FALSE);
	}

	res_z<-prcomp(mat, center=T, scale=T)
	s <- min(30, ncol(res_z$rotation))
	if (s > 3) {
		write.table(res_z$rotation[,1:s], file=z_loading_file, sep='\t', col.names=FALSE, quote = FALSE);
		write.table(res_z$x[,1:3], file=z_coord_file, sep='\t', col.names=FALSE, quote = FALSE);
		write.table(res_z$sdev, file=z_std_file, sep='\t', col.names=FALSE, quote = FALSE);
	}
}
print("done.")
