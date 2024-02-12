hmm_out=$(mktemp)
../bin/hmmer/binaries/hmmscan --domtblout $hmm_out -E 1e-5 --domE 1e-5 ../bin/hmmer/pfam/Pfam-A.hmm $1
grep -v '^#' $hmm_out | perl -lane 'print "$F[3]\t$F[0]\t$F[19]\t$F[20]"' | sort -k 3 -n > $2
