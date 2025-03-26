#!/bin/bash
home=/var/www/html/clinomics
script_file=`realpath $0`
script_home=`dirname $script_file`
log_home=$home/storage/logs/`date +"%Y-%m"`
mkdir -p $log_home
log_file=${log_home}/`date +"%Y-%m-%d-%H:%M:%S"`.log
project=processed_DATA
sync_dir=$home/storage/sync/update_list
data_dir=$home/storage/ProcessedResults/${project}

today=${sync_dir}/today_list_${project}.txt
yesterday=${sync_dir}/yesterday_list_${project}.txt
new=${sync_dir}/new_list_${project}.txt

echo -n > $new
echo -n > $yesterday
cp $today $yesterday
stat -c "%n %Y" ${data_dir}/*/*/successful.txt > $today
stat -c "%n %Y" ${data_dir}/*/*/failed_delete.txt >> $today
grep -Fvxf ${yesterday} ${today} | cut -d' ' -f1 | rev | cut -d'/' -f 1-3 | rev >${new}
${script_home}/uploadCase.pl -i $data_dir -l $new -d $project >> $log_file
