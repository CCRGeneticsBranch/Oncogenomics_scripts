for fn in /mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/storage/ProcessedResults/processed_DATA/*/*/*/cnvkit/*.pdf;do
	bn="${fn%.pdf}"
	bn=$(basename "$bn")
	dest_dir=$(dirname "$fn")
	dn=$(dirname "$dest_dir")
	sample_id=$(basename "$dn")
	dn=$(dirname "$dn")
        case_id=$(basename "$dn")
	dn=$(dirname "$dn")
        patient_id=$(basename "$dn")
	echo "$patient_id/$case_id/$sample_id/cnvkit/$bn.png"
	scp -q biowulf:/data/khanlab/projects/processed_DATA/$patient_id/$case_id/$sample_id/cnvkit/$bn.png $dest_dir
done
