script_home_dev=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/scripts/backend
script_home_production=/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics/app/scripts/backend
$script_home_production/refreshViews.pl -v &	
$script_home_dev/refreshViews.pl -v
