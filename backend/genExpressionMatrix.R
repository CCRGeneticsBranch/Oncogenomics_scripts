suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tibble))

Args<-commandArgs(trailingOnly=T)
meta_file<-Args[1]
annotation_file <- Args[2]
out_file <- Args[3]

options(matrixStats.useNames.NA = "deprecated")

#meta_file <- "/mnt/projects/CCR-JK-oncogenomics/static/data/javed/all_ribozero_samples.tsv"
#annotation_file <- "/mnt/projects/CCR-JK-oncogenomics/static/ref/RSEM/gencode.v36lift37.annotation.txt"
#out_file <- "/mnt/projects/CCR-JK-oncogenomics/static/data/javed/all_ribozero_samples_log2TPM.tsv"

meta <- read.table(meta_file, header=T, sep="\t", fill=T)
colnames(meta) <- tolower(colnames(meta))

#meta <- meta[c(1:5),]

anno <- read.table(annotation_file, header=T, sep="\t", fill=T)
tpm_mats <- anno

print("making matrix...")
count_mats <- anno
data_root <- "/mnt/projects/CCR-JK-oncogenomics/static/ProcessedResults"
suffix <- ".rsem_ENS.genes.results.tpm.txt"
suffix2 <- ".genes.results.tpm.txt"
folder <- "RSEM_ENS"
# 1. Fixed initialization (split into separate lines)
tpm_mats <- anno  
meta_mats <- NULL 

for (i in c(1:nrow(meta))) {
    patient_id <- meta$patient_id[i]
    case_id <- meta$case_id[i]
    sample_id <- meta$sample_id[i]
    sample_name <- meta$sample_name[i]
    path <- meta$path[i]
    rsem_file <- ""
    
    case_root <- paste0(data_root, "/", path, "/", patient_id, "/", case_id)
    
    # Check file paths
    if (file.exists(paste0(case_root, "/", sample_id, "/", folder, "/", sample_id, suffix))) {
        rsem_file <- paste0(case_root, "/", sample_id, "/", folder, "/", sample_id, suffix)
    } else if (file.exists(paste0(case_root, "/", sample_name, "/", folder, "/", sample_name, suffix))) {
        rsem_file <- paste0(case_root, "/", sample_name, "/", folder, "/", sample_name, suffix)
    } else if (file.exists(paste0(case_root, "/", sample_name, "/", folder, "/", sample_name, suffix2))) {
        rsem_file <- paste0(case_root, "/", sample_name, "/", folder, "/", sample_name, suffix2)
    } else if (file.exists(paste0(case_root, "/Sample_", sample_id, "/", folder, "/Sample_", sample_id, suffix))) {
        rsem_file <- paste0(case_root, "/Sample_", sample_id, "/", folder, "/Sample_", sample_id, suffix)
    } else {
        print(paste0("Sample ", sample_id, " not found"))
    } # 3. Added closing brace for 'else'
    
    # Move this block INSIDE the for loop
    if (rsem_file != "") {
        data <- as.data.frame(data.table::fread(rsem_file, sep="\t", header = TRUE))
        tpm <- data %>% dplyr::select(gene_id, TPM)
        
        if (substr(data$gene_id[1], 1, 4) == "ENSG") {
            tpm$gene_id <- gsub("\\..*","",tpm$gene_id)
            tpm <- tpm %>% group_by(gene_id) %>% summarise(TPM = sum(TPM))
            tpm_mats <- tpm_mats %>% inner_join(tpm, by=c("gene_id"="gene_id"))
        } else {
            # 5. Fixed column name mapping to join by 'gene_id' instead of 'gene_name'
            tpm_mats <- tpm_mats %>% inner_join(tpm, by=c("gene_id"="gene_id"))
            
            # NOTE: If you need count_mats, you must define 'count_mats' and 'count' 
            # somewhere above before you can use them here.
        }
        
        # Rename the newly added column to the specific sample_id
        colnames(tpm_mats)[ncol(tpm_mats)] = sample_id
        
        # Build metadata matrix
        if (is.null(meta_mats)) {
            meta_mats <- t(meta[i, ])
        } else {
            meta_mats <- cbind(meta_mats, t(meta[i, ]))
        }
    }
} # 1. Loop now closes correctly at the very end


tpm_coding <- tpm_mats %>% dplyr::filter(gene_type == "protein_coding")
tpm_coding <- tpm_coding[,c(8,10:ncol(tpm_coding))]
tpm_coding <- as.data.frame(tpm_coding %>% dplyr::group_by(gene_name) %>% dplyr::summarise_all(list(mean)))
rownames(tpm_coding) <- tpm_coding$gene_name
tpm_coding$gene_name <- NULL
tpm_coding <- round(log2(tpm_coding+1),3)
colnames(meta_mats) <- colnames(tpm_coding)
tpm_coding <- as.data.frame(rbind(meta_mats[c(1,3,5,6),],tpm_coding))

write.table(tpm_coding, out_file, sep="\t", row.names = T, col.names=NA, quote = FALSE)

