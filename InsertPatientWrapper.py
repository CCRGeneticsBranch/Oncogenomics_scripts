import re
import requests
import os,subprocess
import json
import sys
import csv
import shutil
import glob
import time
import urllib
import os,subprocess

def main():
	#loadVarPatients2 IS FOR SPLICING, FOR NON PLICING USE loadVarPatients.pl
	#User input:
			#1. patient file list
			#2. Where patient folders are located 
			#3. which tier to insert
	patient_file=sys.argv[1]
	input_folder=sys.argv[2]
	tier=sys.argv[3]
	types=sys.argv[4]
	insert(patient_file,input_folder,tier,types)

def insert(patient_file,input_folder,tier,types):
	if tier == 'dev':
		tier='clinomics_dev'
	if tier== 'production':
		tier='clinomics'
	if  tier =='public':
		tier='clinomics_dev2'
	fh= open(patient_file)
#	log_file = open("/mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev2/app/scripts/backend/InsertPatientWrapperLogs.txt", "w")

	lines=fh.readlines()
	for line in lines:
		patient_id=line.rstrip()
		cmd="perl /mnt/webrepo/fr-s-bsg-onc-d/htdocs/"+tier+"/app/scripts/backend/loadVarPatients.pl -t "+types+" -p "+patient_id+" -i /mnt/webrepo/fr-s-bsg-onc-d/htdocs/clinomics_dev/app/storage/ProcessedResults/"+input_folder
		print cmd+"\n"
#		log_file.write(cmd)
		os.system(cmd)
main()



 
