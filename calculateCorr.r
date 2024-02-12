Args<-commandArgs(trailingOnly=T)
RDSfile<-Args[1]
gene <- Args[2]
outFile <- Args[3]
method <- Args[4]

start_time <- Sys.time()
# RDSfile <- '/var/www/html/clinomics/storage/project_data/23716/ensembl-gene-coding.all.tmm-rpkm.rds'
# gene <- 'MYCN'
# outFile <- '/var/www/html/clinomics/storage/project_data/23716/cor/ensembl-pearson.tmm-rpkm.MYCN.tsv'
# method <- 'pearson'

#RDSfile=paste("/var/www/html/clinomics/storage/project_data/",projectId,"/",targetType,"-gene-coding.rds",sep="")

exp_data=readRDS(RDSfile)
#if there are duplicate gene names
if (colnames(exp_data)[1] == "X") {
	rownames(exp_data) <- make.names(exp_data$X, unique=TRUE)
	exp_data <- exp_data[,2:ncol(exp_data)]
}
#exp_date=as.data.frame(data.table::fread(RDSfile, header=T, sep="\t"))
#exp<-exp_data[2:nrow(exp_data),2:ncol(exp_data)]
#exp <- as.data.frame(lapply(exp, function(x) as.numeric(as.character(x))))
exp_mat<-as.matrix(exp_data) # convert to matrix
#rownames(exp_mat)<-exp_data[,1]

exp_mat=t(exp_mat)
class(exp_mat)<-"numeric"
exp_mat=log(exp_mat+1,2)

queryGene=as.vector(exp_mat[,gene])

corMat=t(cor(queryGene,exp_mat, method=c(method))) # type can be pearson or spearman
corSlim=corMat[!abs(corMat) <=0.2,]
finalMat=as.matrix(corSlim)
finalMat=cbind(rownames(finalMat),finalMat)

#spearmanCor=t(cor(queryGene,exp_mat, method=c("spearman"))) # type can be pearson or spearman
#spearmanSlim=spearmanCor[!abs(spearmanCor) <=0.2,]
#spearmanMat=as.matrix(spearmanSlim)             
#spearmanMat=cbind(spearmanMat,rownames(spearmanMat))

write.table(finalMat, file=outFile, quote = FALSE, sep='\t',row.names =FALSE,col.names=FALSE)
#write.table(spearmanMat, file=paste(outDir,gene,"SpearmanCoeficient.tsv",sep=""),sep='\t',row.names =FALSE,col.names=FALSE)

end_time <- Sys.time()
time_exec=end_time - start_time
#print (time_exec)
