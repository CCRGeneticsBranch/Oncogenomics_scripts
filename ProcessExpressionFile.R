library(dplyr)
Args<-commandArgs()

inFile<-Args[6]
annotationRDS <- Args[7]
outDIR <- Args[8]
exp_sample_id <- Args[9]
print (inFile)
print (annotationRDS)
print (outDIR)
print (exp_sample_id)

#annotationRDS=("./TPM_upload/Annotation/annotation_ENSEMBL_gene_19.RDS")
#exp_sample_id="Sample012345"

#inFile="./TPM_upload/gene_ens_upload_example.txt"
#inFile="./TCGA/diagnosis_h38_processed/ACC/IlluminaHiSeq_RNAseqV2/tumor/counts/TCGA-OR-A5J1-01A.htseq.counts"
#outDIR="./TPM_upload/NCI0002/20160415/test_sample/TPM_ENS/"
outFileRDS=paste(exp_sample_id, "_counts.gene.fc.RDS",sep="")
outFileTXT=paste(exp_sample_id, "_counts.gene.txt",sep="")

Annotation=readRDS(annotationRDS)
count_data<-read.table(inFile, header=FALSE, com='', sep="\t")
count_data$V1=gsub("\\..*","",count_data$V1)


exists=subset(count_data, count_data$V1 %in% Annotation$GeneID)
missing=as.data.frame((setdiff(Annotation$GeneID,exists$V1)))
colnames(exists)=c("GeneID",exp_sample_id)
new_counts=exists

if(nrow(missing)>1){
  missing$V2<- as.integer(0)
  colnames(missing)=c("GeneID",exp_sample_id)
  new_counts <- rbind(exists, missing)
}
  
  coords=merge(new_counts,Annotation,by="GeneID")
  coords=coords[c("Chr","Start","End","GeneID","Length",exp_sample_id)]
  write.table(coords, file=paste(outDIR,outFileTXT,sep=""), sep='\t', col.names=TRUE,row.names =TRUE)
  List <- list()
  counts<-new_counts[,2]
  counts_mat<-as.matrix(counts) # convert to matrix
  rownames(counts_mat)<-new_counts[,1]
  
  List[["counts"]]<-counts_mat
  saveRDS(List,file=paste(outDIR,outFileRDS,sep=""))

  