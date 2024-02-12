module load oracle
script_home_dev=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/scripts/backend
data_home=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/storage/data

#clinomics_master_file=$data_home/Sequencing_Tracking_Master_clinomics.txt
#khanlab_master_file=$data_home/Sequencing_Tracking_Master.txt
khanlab_master_file=$data_home/Sequencing_Tracking_Master_Public_db.txt
khanlab_modified="1"
echo "Uploading public database..."
$script_home_dev/syncMaster.pl -u -i $khanlab_master_file -m $khanlab_modified


