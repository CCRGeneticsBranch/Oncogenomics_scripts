#!/bin/bash
home=/var/www/html/clinomics
script_file=`realpath $0`
script_home=`dirname $script_file`
log_home=$home/storage/sync/logs/`date +"%Y-%m"`
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
echo "********** 1. Looking for new processed cases **********" >> ${log_file}
grep -Fvxf ${yesterday} ${today} | cut -d' ' -f1 | rev | cut -d'/' -f 1-3 | rev >${new}
echo "********** 2. Uploading data to DB **********" >> ${log_file}
${script_home}/uploadCase.pl -i $data_dir -l $new -d $project >> $log_file
echo "********** 3. Updating case ID **********" >> ${log_file}
${script_home}/updateVarCases.pl >> $log_file
echo "********** 4. Exporting Update case ID **********" >> ${log_file}
${script_home}/export_new_variants.pl >> ${log_file}
echo "********** 5. Refreshing views **********" >> ${log_file}
${script_home}/refreshViews.pl -c -h >> ${log_file}
echo "********** 6. Processing project data **********" >> ${log_file}
${script_home}/../preprocessProjectMaster.pl -p $new -e $EMAILS -u $URL -m -g -c
