Args<-commandArgs()
in_file<-Args[6]
loading_file<-Args[7]
coord_file<-Args[8]
std_file<-Args[9]
do_trans<-Args[10]
data<-read.table(in_file, header=T, com='', sep="\t")
d<-data[,2:length(data)]
mat<-as.matrix(d) # convert to matrix
if (do_trans == 'T') {
	mat<-t(mat)
	colnames(mat)<-data[,1]
} else {
	rownames(mat)<-data[,1]
}
res<-prcomp(mat)
write.table(res$rotation[,1:3], file=loading_file, sep='\t', col.names=FALSE);
write.table(res$x[,1:3], file=coord_file, sep='\t', col.names=FALSE);
write.table(res$sdev, file=std_file, sep='\t', col.names=FALSE);
