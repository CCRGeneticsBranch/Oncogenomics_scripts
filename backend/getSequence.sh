module load blast
blastdbcmd -db $1 -entry $2 -range $3-$4 -outfmt %s