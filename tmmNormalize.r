suppressPackageStartupMessages(library(edgeR))
suppressPackageStartupMessages(library(limma))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tibble))
suppressPackageStartupMessages(library(DESeq2))
suppressPackageStartupMessages(library(sva))
suppressPackageStartupMessages(library(GSVA))
suppressPackageStartupMessages(library(GSEABase))

runGSVA <- function(lcpm, gmt, out_file, method="gsva", kcdf="Gaussian") {
  print(paste0("Running GSVA, gmt=",gmt,", out_file=", out_file, ", method=", method))
  gs <- getGmt(gmt)
  if (method == "gsva")
    gsva_par <- gsvaParam(as.matrix(lcpm), gs, kcdf=kcdf)
  if (method == "ssgsea")
    gsva_par <- ssgseaParam(as.matrix(lcpm), gs)
  if (method == "zscore")
    gsva_par <- zscoreParam(as.matrix(lcpm), gs)
  gsva <- gsva(gsva_par)
  gsva <- round(gsva,3)
  write.table(as.data.frame(gsva), out_file, row.names = T, col.names = NA, sep="\t", quote=F)
}

runPCA <- function(lcpm, file_prefix, var_gene_num=1000) {
    print("Running PCA")
    mat <- as.matrix(lcpm)
    mat<-t(mat)
    class(mat)<-"numeric"      
    lib_type <- "all"
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

Args<-commandArgs(trailingOnly=T)
exp_list_file<-Args[1]
annotation_file <- Args[2]
out_dir <- Args[3]

options(matrixStats.useNames.NA = "deprecated")

#exp_list_file <- "/var/www/html/clinomics_dev/app/storage/project_data/22112/exp_list-ensembl-gene.tsv"
#annotation_file <- "/var/www/html/clinomics_dev/app/storage/data/gencode.v19.annotation.txt"
#out_dir <- "/var/www/html/clinomics_dev/app/storage/project_data/22112"

exp_list <- read.table(exp_list_file, header=F, sep="\t", fill=T)
colnames(exp_list) <- c("sample_id", "sample_name", "file", "library_type", "tissue_type")
sample_names <- exp_list$sample_name
batch <- as.factor(exp_list$library_type)
tissue_type <- as.factor(exp_list$tissue_type)

anno <- read.table(annotation_file, header=T, sep="\t", fill=T)

print("making matrix...")
count_mats <- anno
tpm_mats <- anno
sample_names <- c()
batch <- c()
tissue_type <- c()
for (i in c(1:length(exp_list$file))) {
  file <- exp_list$file[i]
  sample_id <- exp_list$sample_id[i]
  sample_name <- exp_list$sample_name[i]
  library_type <- exp_list$library_type[i]
  t <- exp_list$tissue_type[i]
  data <- as.data.frame(data.table::fread(file, sep="\t", header = TRUE))
  count <- data %>% dplyr::select(gene_id, expected_count)
  tpm <- data %>% dplyr::select(gene_id, TPM)
  if (count$gene_id[1] == ".") {
    count <- data %>% dplyr::select(symbol, expected_count)
    tpm <- data %>% dplyr::select(symbol, TPM)
    colnames(count)[1] <- "gene_id"
    colnames(tpm)[1] <- "gene_id"
  }
  if (substr(data$gene_id[1], 1, 4) == "ENSG") {    
    #count$gene_id <- gsub("\\..*","",count$gene_id)
    count$gene_id <- gsub("\\.[0-9]*_[0-9]*","",count$gene_id)
    count <- count %>% group_by(gene_id) %>% summarise(expected_count = sum(expected_count))
    #tpm$gene_id <- gsub("\\..*","",tpm$gene_id)
    tpm$gene_id <- gsub("\\.[0-9]*_[0-9]*","",tpm$gene_id)
  tpm <- tpm %>% group_by(gene_id) %>% summarise(TPM = sum(TPM))
    count_mats <- count_mats %>% inner_join(count, by=c("gene_id"="gene_id"))
    tpm_mats <- tpm_mats %>% inner_join(tpm, by=c("gene_id"="gene_id"))
  } else {
    count_mats <- count_mats %>% inner_join(count, by=c("gene_name"="gene_id"))
    tpm_mats <- tpm_mats %>% inner_join(tpm, by=c("gene_name"="gene_id"))
  }
  colnames(count_mats)[ncol(count_mats)] = sample_id
  colnames(tpm_mats)[ncol(tpm_mats)] = sample_id
  sample_names[length(sample_names)+1] <- sample_name
  batch[length(batch)+1] <- library_type
  tissue_type[length(tissue_type)+1] <- t
}

write.table(count_mats, paste(out_dir,"/expression.count.tsv", sep= ""), sep="\t",row.names = F, col.names=T, quote = FALSE)
write.table(tpm_mats, paste(out_dir,"/expression.tpm.tsv", sep= ""), sep="\t",row.names = F, col.names=T, quote = FALSE)

tpm_coding <- tpm_mats %>% dplyr::filter(gene_type == "protein_coding")
coding_ids <- tpm_coding$gene_id
tpm_mats <- NULL
tpm_coding <- tpm_coding[,10:ncol(tpm_coding)]
rownames(tpm_coding) <- coding_ids
write.table(tpm_coding, paste(out_dir,"/expression.tpm.coding.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
tpm_coding_zscore <- round(t(scale(t(tpm_coding))),2)
write.table(tpm_coding_zscore, paste(out_dir,"/expression.tpm.coding.zscore.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
tpm_coding_rank <- as.data.frame(t(apply(tpm_coding, 1, function(x) rank(-x, ties.method="min"))))
colnames(tpm_coding_rank) <- colnames(tpm_coding)
write.table(tpm_coding_rank, paste(out_dir,"/expression.tpm.coding.rank.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
saveRDS(tpm_coding, paste(out_dir,"/expression.coding.tpm.RDS", sep= ""))
tpm_coding <- NULL
gc()
count_mats <- count_mats %>% dplyr::filter(gene_type == "protein_coding")
genes <- count_mats %>% dplyr::select(gene_id, length)
anno <- count_mats[,1:9]
counts <- count_mats[,10:ncol(count_mats)]
rownames(counts) <- count_mats$gene_id
genes_anno <- count_mats %>% dplyr::select(gene_id, gene_name)
count_mats <- NULL
gc()
dge <- DGEList(counts=counts, genes=genes)
dge <- calcNormFactors(dge, method = "TMM")
lcpm <- as.matrix(cpm(dge, log=T))
rpkm <- as.data.frame(rpkm(dge))
rpkm <- round(rpkm,2)
design <- matrix(1,ncol(lcpm),1)
if (!is.null(tissue_type) && nlevels(tissue_type) > 1) {
    x <- data.frame("group"=as.factor(as.character(tissue_type)))
    design <- model.matrix(~group, data=x)            
}
v <- voom(dge, design, plot=F)
lcpm <- as.data.frame(v$E)
runPCA(lcpm, paste(out_dir,"/pca",sep=""))
lcpm$gene_id <- rownames(lcpm)
lcpm <- lcpm %>% dplyr::inner_join(genes_anno, by=c("gene_id"="gene_id"))
lcpm$gene_id <- NULL
lcpm <- as.data.frame(lcpm %>% dplyr::group_by(gene_name) %>% dplyr::summarise_all(list(mean)))
rownames(lcpm) <- lcpm$gene_name
lcpm$gene_name <- NULL
colnames(lcpm) <- sample_names
dge <- NULL
gc()

if (1 == 2) {
  min_count <- 10
  min_sample <- 2
  meta <- exp_list
  rownames(meta) <- meta$sample_id
  dds <- DESeqDataSetFromMatrix(countData=round(counts), colData=meta, design=~ tissue_type)
  keep <- rowSums( counts(dds) >= min_count ) >= min_sample
  dds <- dds[keep,]
  vst <- vst(dds)
  lcpm <- as.data.frame(assay(vst))
}

#remove library type effect
if (!is.null(batch) && nlevels(batch) > 1) {
    lrpkm  <- log2(rpkm + 1)
    print("removing library type effect")              
    lcpm <- removeBatchEffect(lcpm, batch, design=design)
    lrpkm <- removeBatchEffect(lrpkm, batch, design=design)
    lrpkm <- ifelse(lrpkm < 0, 0, lrpkm)
    rpkm <- 2^lrpkm - 1
    lrpkm <- NULL
    gc()
}
rpkm <- as.data.frame(round(rpkm,2))
rpkm$gene_id <- rownames(rpkm)
rpkm <- anno %>% inner_join(rpkm, by=c("gene_id"="gene_id"))
write.table(rpkm, paste(out_dir,"/expression.tmm-rpkm.tsv", sep= ""), sep="\t",row.names = F, col.names=T, quote = FALSE)
rpkm_coding <- rpkm %>% filter(gene_type == "protein_coding")
coding_ids <- rpkm_coding$gene_id
rpkm_coding <- rpkm_coding[,10:ncol(rpkm_coding)]
rownames(rpkm_coding) <- coding_ids
saveRDS(rpkm_coding, paste(out_dir,"/expression.coding.tmm-rpkm.RDS", sep= ""))
rpkm <- NULL
rpkm_coding <- NULL
gc()
#runPCA(lcpm, paste(out_dir,"/pca",sep=""))

write.table(genes_anno, paste(out_dir,"/genes.tsv", sep= ""), sep="\t",row.names = F, col.names=T, quote = FALSE)
write.table(lcpm, paste(out_dir,"/expression.lcpm.tsv", sep= ""), sep="\t",row.names = T, col.names=NA, quote = FALSE)
gmts <- c("c2.all.v2024.1.Hs.symbols.gmt","c6.all.v2024.1.Hs.symbols.gmt","CytoSig_Top250.gmt","c7.immunesigdb.v2024.1.Hs.symbols.gmt","h.all.v2024.1.Hs.symbols.gmt","NCI_GeneSet_v38.gmt")
methods <- c("gsva", "ssgsea", "zscore")
gsva_out_dir <- paste0(out_dir, "/gsva")
dir.create(gsva_out_dir, showWarnings = FALSE)
for (gmt in gmts) {
  gmt_file <- paste0(out_dir, "/../../../app/ref/msigdb/", gmt)
  for (method in methods) {
    gsva_out_file <- paste0(gsva_out_dir, "/", gsub("\\.gmt", "", gmt), ".", method, ".txt")
    runGSVA(lcpm, gmt_file, gsva_out_file, method)
  }
}
