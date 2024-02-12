export NODE_PATH=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.sandbox1/public/node/node_modules

script_home=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.sandbox1/app/scripts/backend
data_home=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.sandbox1/app/storage/data

excel_file=$data_home/Sequencing_Tracking_Master.xlsx
if [ ! -f $excel_file ]
then
	before_modify_time=""
else
	before_modify_time=`stat --printf=%y $excel_file`
fi
rsync -aiz biowulf2:/data/khanlab/projects/DATA/Sequencing_Tracking_Master/Sequencing_Tracking_Master.xlsx $data_home/
after_modify_time=`stat --printf=%y $excel_file`
if [ "$before_modify_time" !=  "$after_modify_time" ]
then
	echo "Converting xlsx to json..."
	#echo "/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.sandbox1/public/node/bin/node $script_home/xlsx2json.js"
	/mnt/webrepo/fr-s-bsg-onc-d/htdocs/onco.sandbox1/public/node/bin/node $script_home/xlsx2json.js
	echo "Converting json to tsv..."
	#echo "php $script_home/json2tsv.php in=$data_home/Sequencing_Tracking_Master.json > $data_home/Sequencing_Tracking_Master.tsv"
	php $script_home/json2tsv.php in=$data_home/Sequencing_Tracking_Master.json > $data_home/Sequencing_Tracking_Master.tsv
	echo "Uploading database..."
	$script_home/load_master_sheet.pl -i $data_home/Sequencing_Tracking_Master.tsv,$data_home/SequencingMasterFile.txt
	#$script_home/load_master_sheet.pl -i $data_home/SequencingMasterFile.txt
	#rm $data_home/Sequencing_Tracking_Master.tsv
else
	echo "Young's master file is not updated"
fi

khanlab_master_file=$data_home/Sequencing_Tracking_Master.txt
clinomics_master_file=$data_home/SequencingMasterFile.txt
if [ ! -f $khanlab_master_file ]
then
	before_khanlab_modify_time=""
else
	before_khanlab_modify_time=`stat --printf=%y $khanlab_master_file`
fi

if [ ! -f $clinomics_master_file ]
then
	before_clinomics_modify_time=""
else
	before_clinomics_modify_time=`stat --printf=%y $clinomics_master_file`
fi

rsync -aiz biowulf2:/data/khanlab/ref/MasterFile/SequencingMasterFile.txt $data_home/
rsync -aiz biowulf2:/data/khanlab/ref/MasterFile/Sequencing_Tracking_Master.txt $data_home/
after_khanlab_time=`stat --printf=%y $khanlab_master_file`
after_clinomics_time=`stat --printf=%y $clinomics_master_file`
if [ "$before_khanlab_modify_time" !=  "$before_khanlab_modify_time" ] || [ "$before_clinomics_modify_time" !=  "$after_clinomics_time" ]
then
	echo "Uploading database..."
	$script_home/load_master_sheet.pl -i $data_home/Sequencing_Tracking_Master.txt,$data_home/SequencingMasterFile.txt	
	#$script_home/load_master_sheet.pl -i $data_home/SequencingMasterFile.txt	
else
	echo "Rajesh's master file is not updated"
fi

#select s1.sample_id, s1.patient_id, s1.biomaterial_id, s1.source_biomaterial_id, s1.exp_type, s1.tissue_cat, s1.tissue_type, s2.sample_id as normal_sample from samples s1, samples s2 where s1.patient_id=s2.patient_id and s1.tissue_cat='tumor' and s2.tissue_cat in ('normal','blood') and s1.exp_type=s2.exp_type and s1.platform='Illumina' and s2.platform='Illumina' and s1.relation='self' and s2.relation='self' order by s1.sample_id
#select s1.sample_id, s1.patient_id, s1.biomaterial_id, s1.source_biomaterial_id, s1.exp_type, s1.tissue_cat, s1.tissue_type, s2.sample_id as rna_sample from samples s1, samples s2 where s1.patient_id=s2.patient_id and s1.tissue_cat='tumor' and s1.exp_type <> 'RNAseq' and s2.exp_type='RNAseq' and s1.source_biomaterial_id=s2.source_biomaterial_id and s1.platform='Illumina' and s2.platform='Illumina' and s1.relation='self' and s2.relation='self' order by s1.sample_id
