suppressPackageStartupMessages(library(dplyr))
options(warn = -1)
Args<-commandArgs(trailingOnly=T)
rds_file<-Args[1]
tpm_file<-Args[2]
out_file<-Args[3]
gtex_fc <- readRDS(rds_file)
tpm <- read.table(tpm_file,head=T,sep="\t")
colnames(tpm)[6] <- "TPM"
countObj <- as.data.frame(gtex_fc$counts)
annoObj <- as.data.frame(gtex_fc$Annotaton)
colnames(countObj) <- c("count")
countObj$GeneID <- rownames(countObj)
joined <- countObj %>% inner_join(annoObj, by=c("GeneID"="GeneID"))
rsemObj <- joined %>% dplyr::inner_join(tpm,by=c("Chr"="Chr","Start"="Start","End"="End","GeneName"="GeneName","Length"="Length")) %>% dplyr::select(GeneName,Length,TPM,count) %>% group_by(GeneName) %>% summarize(Length=mean(Length),TPM=mean(TPM),count=mean(count)) %>% arrange(GeneName)
rsemObj$GeneID="."
rsemObj$FPKM="."
rsemObj$EffectLength=rsemObj$Length
rsemObj <- rsemObj %>% dplyr::select(GeneName, GeneID, Length, EffectLength, count, TPM, FPKM)
colnames(rsemObj) <- c("symbol","gene_id","length","effective_length","expected_count","TPM","FPKM")
write.table(rsemObj, out_file, quote=F, sep="\t", row.names=F, col.names=T)