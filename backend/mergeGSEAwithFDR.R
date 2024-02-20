#merge GSEA results
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(pheatmap))

args <- commandArgs(trailingOnly = T)

meta_file <- args[1]
out_prefix <- args[2]
th <- 0.25
if(length(args) == 3)
  th <- args[3]
#setwd("X:/hsienchao/Natasha/processed_DATA/chained/kallisto_quant_out/DE")
#meta_file <- "gsea_nci_meta.txt"
#out_prefix <- "gsea_nci"
#meta_file <- "gsea_c2_meta.txt"
#out_prefix <- "gsea_c2"

merged <- NULL
merged_sig <- NULL
meta <- read.table(meta_file, head=F)
colnames(meta) <- c("Sample","Path")
samples <- unique(meta$Sample)
samples_merged = samples
samples_sig = samples
for (sample in samples) {
  sub_meta <- meta %>% dplyr::filter(Sample == sample)
  gsea_all <- NULL
  gsea_sig_all <- NULL
  for (path in sub_meta$Path) {
    #print(path)
    gsea <- read.table(path, header=T, sep="\t")
    gsea_sig <- gsea %>% dplyr::filter(FDR.q.val <= th) %>% dplyr::select(NAME, NES)
    gsea <- gsea %>% dplyr::select(NAME, NES, FDR.q.val)
	#rbind both positive and negative
    gsea_all <- rbind(gsea_all, gsea)	
    gsea_sig_all <- rbind(gsea_sig_all, gsea_sig)    
  }
  colnames(gsea_all) <- c("NAME", paste0(sample,".NES"), paste0(sample,".FDR"))
  if (is.null(merged)) {
    merged <- gsea_all
    merged_sig <- gsea_sig_all
  } else {
    if (nrow(gsea_all) > 0)
        merged <- merged %>% full_join(gsea_all, by=c("NAME"="NAME"))
    else
        samples_merged <- samples_merged[!(samples_merged %in% c(sample))]
    if (nrow(gsea_sig_all) > 0)
        merged_sig <- merged_sig %>% full_join(gsea_sig_all, by=c("NAME"="NAME"))
    else
        samples_sig <- samples_sig[!(samples_sig %in% c(sample))]
  }
}

#colnames(merged) <- c("NAME", samples_merged)
colnames(merged_sig) <- c("NAME", samples_sig)
#merged[is.na(merged)] <- 0
#merged_sig[is.na(merged_sig)] <- 0
write.table(merged, paste(out_prefix, "_all.txt", sep=""), row.names = F, col.names = T, sep="\t", quote=F)
write.table(merged_sig, paste(out_prefix, "_fdr", th, ".txt", sep=""), row.names = F, col.names = T, sep="\t", quote=F)
merged_sig <- merged %>% dplyr::filter(NAME %in% merged_sig$NAME)
rownames(merged_sig) <- merged_sig$NAME
merged_sig$NAME <- NULL

#pdf(paste(out_prefix, "_fdr", th, ".pdf", sep=""))
#pheatmap(merged_sig, fontsize_row=6, show_rownames=F)
#dev.off()


#pdf(paste(out_prefix, "_fdr", th, "NegSF3B1.pdf", sep=""))
#pheatmap(merged_sig %>% dplyr::filter(FLI1 > 2 & HNRNPH1 > 2 & SF3B1 < 1), fontsize_row=8)
#dev.off()
#pdf(paste(out_prefix, "_fdr", th, "PosSF3B1.pdf", sep=""))
#pheatmap(merged_sig %>% dplyr::filter(FLI1 < 0.5 & HNRNPH1 < 0.5 & SF3B1 > 1.5), fontsize_row=8)
#dev.off()