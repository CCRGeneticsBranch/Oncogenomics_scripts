mapping_file=$1

url=https://fr-s-bsg-onc-d.ncifcrf.gov/clinomics/public
script_dir=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/scripts/backend
src_dir=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/storage/ProcessedResults/nbl
dest_dir=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/storage/ProcessedResults/processed_DATA
case_id=WholeGenome
dirs=( Actionable annotation qc )
while IFS=$'\t' read -r -a cols; do
	new_id=${cols[0]}
	old_id=${cols[1]}
	if [ -d $src_dir/$old_id/$case_id ]; then
		cp -r $src_dir/$old_id/$case_id $dest_dir/$new_id/
		for d in "${dirs[@]}";do
			for f in $src_dir/$old_id/$case_id/$d/*;do
				bn=$(basename "$f")
				if [[ "$bn" == *"$old_id"* ]]; then
					new_f=`echo $bn | sed "s/$old_id/$new_id/"`
					mv $dest_dir/$new_id/$case_id/$d/$bn $dest_dir/$new_id/$case_id/$d/$new_f
				fi
			done
		done		
		for f in $src_dir/$old_id/$case_id/$old_id/db/*;do
			bn=$(basename "$f")
			if [[ "$bn" == *"$old_id"* ]]; then
				new_f=`echo $bn | sed "s/$old_id/$new_id/"`
				mv $dest_dir/$new_id/$case_id/$old_id/db/$bn $dest_dir/$new_id/$case_id/$old_id/db/$new_f
			fi			
		done
		mv $dest_dir/$new_id/$case_id/$old_id $dest_dir/$new_id/$case_id/$new_id
		$script_dir/loadVarPatients.pl -i $dest_dir -p $new_id -c $case_id
	else
		echo "Error: $src_dir/$old_id/$case_id Not Found!"
	fi
done < $mapping_file


