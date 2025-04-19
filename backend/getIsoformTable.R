suppressPackageStartupMessages(library(reshape))
suppressPackageStartupMessages(library(dplyr))
#example 
#Rscript /mnt/projects/CCR-JK-oncogenomics/static/site_data/prod/app/scripts/backend/getIsoformTable.R TCF3.count.tsv TCF3.count.table.tsv Y
Args<-commandArgs(trailingOnly=T)
in_file<-Args[1]
out_file<-Args[2]
include_diag<-Args[3]

df <- read.table(in_file,sep="\t")
colnames(df) <- c("Sample","Diag","Transcript","Value")
df <- df %>% arrange(Diag)
meta <- df %>% dplyr::select(Sample, Diag) %>% distinct() %>% arrange(Diag)
df_cast <- cast(df, Transcript ~ Sample, mean, value = 'Value')
rownames(df_cast) <- df_cast$Transcript
df_cast$Transcript <- NULL
df_cast_sort <- df_cast[,meta$Sample]
if (include_diag == "Y")
	df_cast_sort <- rbind(meta$Diag, df_cast_sort)
write.table(df_cast_sort, out_file, row.names=T, col.names=NA, sep="\t", quote=F)
