suppressPackageStartupMessages(library(edgeR))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tibble))
suppressPackageStartupMessages(library(sva))

makeMatrix <- function(x){
  #print(paste(x))
  #count_table <- read.csv(paste(x, sep=""), sep="\t", header=FALSE, stringsAsFactors = FALSE)
  #data <- read.table(x, head=T, sep="\t")
  data <- as.data.frame(data.table::fread(x, sep="\t", header = TRUE))
  colnames(data) <- c(gsub("\\.rsem.*.", "", basename(x)))  
  return(data)  
}


fpkmToTpm <- function(fpkm){
    exp(log(fpkm) - log(sum(fpkm)) + log(1e6))
  }


normalize <- function(countObj, workdir="", annotName = "", method="", fileName="", annotationRDS="", Refcol =1, priorCount=0, merge=T, saveFiles=F,
                        condition="",batch=NULL, group=NULL){

    Annotation <- data.frame(readRDS(annotationRDS))    

    #drop       <- which( apply(countObj,1,sum) <= 1); print(paste("Droping ", length(drop))) ; countObj <- countObj[-drop,]
    #Annotation <- Annotation[-drop,]
        
    if(priorCount == 0) { tolog = FALSE}  else{ tolog = TRUE }
    
    ########################################### Choose the Annotation
    #print(paste("Chooseing the Annotation"))
    if( annotName == "exon")
    {
      #print(paste("I am Exon"))
      rownames(Annotation) <- Annotation$ExonID
      Annotation$ExonID    <- factor(Annotation$ExonID, levels=rownames(countObj))
      Annotation           <- Annotation %>% dplyr::arrange(ExonID)
      
      genesObj <- Annotation[,c("ExonID", "Length")]
    }
    else if(annotName == "trans"){
      rownames(Annotation) <- Annotation$TranscriptID
      Annotation$TranscriptID <- factor(Annotation$TranscriptID, levels=rownames(countObj))
      Annotation <- Annotation %>% dplyr::arrange(TranscriptID)      
      genesObj <- Annotation[,c("TranscriptID", "Length")]
    }
    else{
    	 genesObj <- Annotation %>% dplyr::select(GeneName, Length) %>% group_by(GeneName) %>% summarize(Length=mean(Length)) %>% dplyr::arrange(GeneName)       
       genesObj <- genesObj[match(rownames(countObj), genesObj$GeneName), ]
       write.table(genesObj, "genesObj.txt", quote=F,sep="\t")
    	 #rownames(Annotation) <- Annotation$GeneID
      #Annotation$GeneID <- factor(Annotation$GeneID, levels=rownames(countObj))
      #Annotation           <- Annotation %>% dplyr::arrange(GeneID)
      #Annotation <- Annotation %>% dplyr::filter(GeneID %in% rownames(countObj))
      #genesObj <- Annotation[,c("GeneID", "Length")]
    }
    
    ########################################### Choose the Method 
    #print(paste("Chooseing the Normalization Method"))
    if( method=="EdgeR") {
    
   #### EdgeR
      ##  Make EdgeR Object
      colnames(genesObj) <- c("GeneID", "Length")
      print(annotationRDS)
      print(nrow(countObj))
      print(nrow(genesObj))
      GeneDF_EdgeR       <- DGEList(counts=countObj, genes=genesObj)
      ## Estimate Normalising Factors
      GeneDF.Norm  <- calcNormFactors(GeneDF_EdgeR, refColumn = Refcol) ; 
      ## Regularized Log Transformation using CPM, FPKM & TPM values
      #GeneDF.tpm   <- as.data.frame(cpm(GeneDF.Norm,  normalized.lib.sizes = TRUE,log = tolog, prior.count = priorCount))
      GeneDF.rpkm  <- as.data.frame(rpkm(GeneDF.Norm, normalized.lib.sizes = T, gene.length=genesObj$Length))
      GeneDF.lrpkm  <- log2(GeneDF.rpkm + 1)
      GeneDF.tpm   <- apply(rpkm(GeneDF.Norm, normalized.lib.sizes = T, gene.length=genesObj$Length), 2 , fpkmToTpm)
      GeneDF.lcpm <- cpm(GeneDF.Norm, log=T)
      #print(nlevels(batch))
      if (!is.null(batch) && nlevels(batch) > 1) {
          print("removing library type effect")          
          design <- matrix(1,ncol(GeneDF.Norm),1)
          if (!is.null(group) && nlevels(group) > 1) {
            x <- data.frame("group"=as.factor(as.character(group)))
            design <- model.matrix(~group, data=x)            
          }
          #GeneDF.voom <- voom(GeneDF.Norm, design=design)          
          #GeneDF.lcpm <- log2(GeneDF.cpm + 1)          
          GeneDF.lcpm <- removeBatchEffect(GeneDF.lcpm, batch, design=design)
          GeneDF.lrpkm <- removeBatchEffect(GeneDF.lrpkm, batch, design=design)
          GeneDF.lrpkm <- ifelse(GeneDF.lrpkm < 0, 0, GeneDF.lrpkm)
          GeneDF.rpkm <- 2^GeneDF.lrpkm - 1

      }      
      GeneDF.lrpkm <- round(GeneDF.lrpkm, 2)
      GeneDF.rpkm <- round(GeneDF.rpkm, 2)
      #GeneDF.ScaledTpm <- t(t(GeneDF.tpm) / GeneDF.Norm$samples$norm.factors)
      #GeneDF.ScaledTpm <- GeneDF.tpm
    }
    else if( method == "DESeq") {
    #### DESeq
      ##Make DESeq Object
      GeneDF_DESeq      <- DESeqDataSetFromMatrix(countData = as.matrix(countObj), colData = DataFrame(condition), design = ~ condition)
      mcols(GeneDF_DESeq)$basepairs <- genesObj$Length-175+1
      ## Estimate SizeFactors
      GeneDF.Norm <- estimateSizeFactors(GeneDF_DESeq)
      ## Regularized Log Transformation using CPM, FPKM & TPM values
      GeneDF.fpm   <- as.data.frame(fpm(object = GeneDF.Norm,  robust = TRUE))
      GeneDF.rpkm  <- as.data.frame(fpkm(object = GeneDF.Norm,  robust = TRUE))
      GeneDF.tpm   <- apply(GeneDF.rpkm, 2 , fpkmToTpm)
    }
     
    ########################################### Prepare final files
    if( annotName == "Exon")
    {
      #GeneDF_Norm_CPM  <- cbind(data.frame(Annotation[,c("Chr","Start","End","GeneID", "GeneName","TranscriptID","ExonID")]), GeneDF.CPM )
      GeneDF_Norm_rpkm <- cbind(data.frame(Annotation[,c("Chr","Start","End","GeneID", "GeneName","TranscriptID","ExonID")]), GeneDF.rpkm )
      GeneDF_Norm_tpm  <- cbind(data.frame(Annotation[,c("Chr","Start","End","GeneID", "GeneName","TranscriptID","ExonID")]), GeneDF.tpm )
      
    }
    else if(annotName == "trans"){
      
      #GeneDF_Norm_CPM  <- cbind(data.frame(Annotation[,c("Chr","Start","End","GeneID","GeneName","TranscriptID")]), GeneDF.CPM )
      GeneDF_Norm_rpkm <- cbind(data.frame(Annotation[,c("TranscriptID", "GeneID", "GeneName")]), GeneDF.rpkm )
      GeneDF_Norm_tpm  <- cbind(data.frame(Annotation[,c("TranscriptID", "GeneID", "GeneName")]), GeneDF.tpm)
      
    }
    else{
      #GeneDF_Norm_CPM  <- cbind(data.frame(Annotation[,c("Chr","Start","End","GeneID","GeneName")]), GeneDF.CPM)
      #GeneDF_Norm_rpkm <- cbind(data.frame(Annotation[,c("GeneID", "GeneID", "GeneName")]), GeneDF.rpkm)
      GeneDF_Norm_rpkm <- GeneDF.rpkm
      #GeneDF_Norm_tpm  <- cbind(data.frame(Annotation[,c("GeneID", "GeneID", "GeneName")]), GeneDF.tpm)
      GeneDF_Norm_tpm <- GeneDF.tpm
    }
    
    ########################################### Choose approprite folder and write files 
    if(merge) {   RawCount=FPKM=CPM=TPM="/MergedFiles/" }
    else { RawCount="/RawCount/"; FPKM="/FPKM/" ; CPM="/CPM/" ; TPM="/TPM"}
  
    if(saveFiles)
    {
      #write.table(countObj, paste(workdir,fileName,"_Count_",annotName,".txt", sep= ""), sep="\t",row.names = FALSE, quote = FALSE)
      #write.table(GeneDF_Norm_rpkm, paste(workdir,fileName,"_Norm_rpkm_",annotName,".txt", sep= ""), sep="\t",row.names = FALSE, quote = FALSE)
      #write.table(GeneDF_Norm_CPM, paste(workdir, fileName,"_Norm_cpm_",annotName,".txt", sep= ""), sep="\t",row.names = FALSE, quote = FALSE)
      #write.table(GeneDF_Norm_tpm, paste(workdir,fileName,"_Norm_tpm_",annotName,".txt", sep= ""), sep="\t",row.names = FALSE, quote = FALSE)
    }
    #print(paste("lcpm row",nrow(GeneDF.lcpm)))
    #print(paste("lcpm col",ncol(GeneDF.lcpm)))
    return(list("tpm" = GeneDF_Norm_tpm, "rpkm" = GeneDF_Norm_rpkm, "lrpkm"=GeneDF.lrpkm, "lcpm"=GeneDF.lcpm))
    
}

runPCA <- function(lcpm, file_prefix, var_gene_num=2000) {

    print("Running PCA")
    mat <- as.matrix(lcpm)
    mat<-t(mat)
    class(mat)<-"numeric"      
    lib_type <- "all"
    #norm_type <- "tmm-rpkm"
    sd_gene <- apply(mat, 2, sd)

    mat <- mat[,which(sd_gene > sort(sd_gene, decreasing=T)[var_gene_num])]
    res<-prcomp(mat)
    loading_file<-paste(file_prefix, "-loading.tsv", sep="");
    coord_file<-paste(file_prefix, "-coord.tsv", sep="");
    std_file<-paste(file_prefix, "-std.tsv", sep="");
    z_loading_file<-paste(file_prefix, "-loading.zscore.tsv", sep="");
    z_coord_file<-paste(file_prefix, "-coord.zscore.tsv", sep="");
    z_std_file<-paste(file_prefix, "-std.zscore.tsv", sep="");      

    s <- min(30, ncol(res$rotation))
    print(paste("s:", s))
    if (s >= 3) {
      write.table(res$rotation[,1:s], file=loading_file, sep='\t', col.names=FALSE, quote = FALSE);
      write.table(res$x[,1:3], file=coord_file, sep='\t', col.names=FALSE, quote = FALSE);
      write.table(res$sdev, file=std_file, sep='\t', col.names=FALSE, quote = FALSE);
    }

    res_z<-prcomp(mat, center=T, scale=T)
    s <- min(30, ncol(res_z$rotation))
    if (s >= 3) {
      write.table(res_z$rotation[,1:s], file=z_loading_file, sep='\t', col.names=FALSE, quote = FALSE);
      write.table(res_z$x[,1:3], file=z_coord_file, sep='\t', col.names=FALSE, quote = FALSE);
      write.table(res_z$sdev, file=z_std_file, sep='\t', col.names=FALSE, quote = FALSE);
    }
}

getColName <- function(x){
  sample <- gsub("Sample_", "", gsub(".*\\.(.*)\\.star_.*", "\\1", c(x)))
  idx <- grep(sample,f[,1])
  if ( identical(idx, integer(0)) ) {
    return (sample)
  }
  return (f[idx[1],2])
}

Args<-commandArgs(trailingOnly=T)
inFile<-Args[1]
geneID_file <- Args[2]
coding_file <- Args[3]
annotationRDS <- Args[4]
annotationType <- Args[5]
outDIR <- Args[6]
outFile <- Args[7]

f<-read.table(inFile, header=F, sep="\t", fill=T)
batch <- f$V4
tissue_type <- f$V5
f<-as.matrix(f)
print("merging count files")
countObj<- do.call(cbind,lapply(paste(f[,3], ".count.txt", sep=""),makeMatrix))
colnames(countObj) <- f[,2]
print("merging TPM files")
tpmObj<- do.call(cbind,lapply(paste(f[,3], ".tpm.txt", sep=""),makeMatrix))
colnames(countObj) <- f[,2]
geneIDs <- read.table(geneID_file, head=T, sep="\t")
coding_genes <- read.table(coding_file, head=F, sep="\t")
rownames(countObj) <- geneIDs[,1]
rownames(tpmObj) <- geneIDs[,1]
coding_list <- as.character(coding_genes$V1)
countCodingObj <- na.omit(subset(countObj, rownames(countObj) %in% coding_list))
tpmCodingObj <- na.omit(subset(tpmObj, rownames(tpmObj) %in% coding_list))
#countCodingObj <- na.omit(countObj[coding_list,])
#tpmCodingObj <- na.omit(tpmObj[coding_list,])
countCodingObj <- countCodingObj[ order(row.names(countCodingObj)), ]
tpmCodingObj <- tpmCodingObj[ order(row.names(tpmCodingObj)), ]
#ltpmObj <- round(log2(tpmObj+1),2)
#ltpmCodingObj <- round(log2(tpmCodingObj+1),2)
#fileList=c("/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.data/ProcessedResults/clinomics/CL0045/20160415/CL0045_T2R_T/TPM_UCSC/CL0045_T2R_T_counts.Gene.fc.RDS","/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.data/ProcessedResults/clinomics/CL0045/20160415/CL0045_T1R_T4/TPM_UCSC/CL0045_T1R_T4_counts.Gene.fc.RDS")
#annotationRDS = "/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/storage/data/AnnotationRDS/annotation_UCSC_gene.RDS"
#countObj <- ComBat_seq(countObj, batch=batch, group=tissue_type)
GeneDF_Norm<-normalize(countObj=countCodingObj, workdir=outDIR, annotName=annotationType, method="EdgeR", annotationRDS=annotationRDS , 
  priorCount=0, fileName=outFile, merge=T, saveFiles=T, batch=batch, group=tissue_type)

runPCA(GeneDF_Norm$lcpm, paste(outDIR,outFile,sep=""))
old_cols <- colnames(GeneDF_Norm$tpm, do.NULL = FALSE)
new_cols <-lapply(old_cols, getColName) 
colnames(GeneDF_Norm$tpm) <- new_cols
colnames(GeneDF_Norm$lrpkm) <- new_cols

print("Saving RDS files")
saveRDS(tpmCodingObj, paste(outDIR,outFile,".coding.tpm.RDS", sep= ""))
saveRDS(GeneDF_Norm$rpkm, paste(outDIR,outFile,".coding.tmm-rpkm.RDS", sep= ""))
#write.table(GeneDF_Norm$tpm, paste(outDIR,outFile,".tpm.tsv", sep= ""), sep="\t",row.names = FALSE, quote = FALSE)
print(paste("Saving ", outDIR,outFile,".all.count.tsv", sep= ""))
write.table(countObj, paste(outDIR,outFile,".all.count.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
print(paste("Saving ", outDIR,outFile,".coding.count.tsv", sep= ""))
write.table(countCodingObj, paste(outDIR,outFile,".coding.count.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
print(paste("Saving ", outDIR,outFile,".all.tpm.tsv", sep= ""))
write.table(tpmObj, paste(outDIR,outFile,".all.tpm.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
#print(paste("Saving ", outDIR,outFile,".all.tpm.log2.tsv", sep= ""))
#write.table(ltpmObj, paste(outDIR,outFile,".all.tpm.log2.tsv", sep= ""), sep="\t",row.names = T, quote = FALSE)
print(paste("Saving ", outDIR,outFile,".coding.tpm.tsv", sep= ""))
write.table(tpmCodingObj, paste(outDIR,outFile,".coding.tpm.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
#print(paste("Saving ", outDIR,outFile,".coding.tpm.log2.tsv", sep= ""))
#write.table(ltpmCodingObj, paste(outDIR,outFile,".coding.tpm.log2.tsv", sep= ""), sep="\t",row.names = T, quote = FALSE)
print(paste("Saving ", outDIR,outFile,".coding.tmm-rpkm.tsv", sep= ""))
write.table(GeneDF_Norm$rpkm, paste(outDIR,outFile,".coding.tmm-rpkm.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
#print(paste("Saving ", outDIR,outFile,".coding.tmm-rpkm.log2.tsv", sep= ""))
#write.table(GeneDF_Norm$lrpkm, paste(outDIR,outFile,".coding.tmm-rpkm.log2.tsv", sep= ""), sep="\t",row.names = T, quote = FALSE)

