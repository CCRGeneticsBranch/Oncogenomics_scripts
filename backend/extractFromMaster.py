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
import codecs
def main():

	#User input:
			#1. input Master File
			#2. project 
			#2. Out directory 
	master_file=sys.argv[1]
	project_list=sys.argv[2]
	outFile=sys.argv[3]
	sample_set = []
	#print(len(sys.argv))
	if len(sys.argv) == 5:
		print("Using sample list: " + sys.argv[4])
		sample_list_file=sys.argv[4]
		sample_set = set([line.rstrip('\n') for line in open(sample_list_file)])
	#patient_list_file=sys.argv[3]	
	#patient_set = set([line.rstrip('\n') for line in open(patient_list_file)])	
	#parseTracking(master_file,project_list,patient_set,outFile)
	parseTracking(master_file,project_list,sample_set,outFile)

def parseTracking(tracking_file,project_list,sample_set,outFile):
	#header_array=["Biomaterial ID","Anatomy/Cell Type","Source Biomaterial ID","Type","Diagnosis","Project","custom ID","Type of sequencing","Matched RNA-seq lib","Enrichment step","Matched normal","Run Start Date","FCID","Library ID","SampleRef","SampleProject","Case Name","seq kit","Protocol no","RIN","DV200","EnhancePipe","PeakCalling","patient_id"]
	print(tracking_file+"\n"+project_list+"\n"+outFile)
	lines=""
	headers=""
	have_headers=False
	file = open(outFile,"w")
	public_projects = set(project_list.split(','))
	sep = '\t'
	
	with open(tracking_file, encoding="ISO8859") as tsvfile:
		reader = csv.DictReader(tsvfile, delimiter='\t')		
		for row in reader:
			line=''
			if have_headers==False:
				header_array=row.keys()
				file.write(sep.join(header_array)+'\n')
				have_headers=True
			#headers = '\t'.join(header_array)
#				have_headers=True
			sample_id = (row['Library ID']+'_'+row['FCID']).rstrip('_')
			if len(sample_set) > 0:
				if sample_id in sample_set:
					row['Project']='RNAseq_Landscape_Manuscript'				
					file.write(sep.join(row.values())+'\n')
			else:
				projects_master_list = row['Project'].split(',')
				projects_master = set([x.strip(' ') for x in projects_master_list])
				projects_inter = projects_master.intersection(public_projects)
				if len(projects_inter) > 0:
					row['Project']=",".join(projects_inter)
					file.write(sep.join(row.values())+'\n')
			"""
			if (row.has_key('patient_id')):
				patient_id = row['patient_id']
			else:
				patient_id = row['custom ID']
			if patient_id in patient_set:
				row['Project']='RNAseq_Landscape_Manuscript'
				file.write(sep.join(row.values())+'\n')
			else:
				patient_id = re.sub('[\s\-()]', '', patient_id);
				if patient_id in patient_set:
					row['Project']='RNAseq_Landscape_Manuscript'
					file.write(sep.join(row.values())+'\n')
				else:
					projects_master_list = row['Project'].split(',')
					projects_master = set([x.strip(' ') for x in projects_master_list])
					projects_inter = projects_master.intersection(public_projects)
					if len(projects_inter) > 0:
						row['Project']=",".join(projects_inter)
						file.write(sep.join(row.values())+'\n')
			"""
				#for header in header_array:
				#	element=row[header]
				#	line=line+element+'\t'
				#line=line.rstrip()
				#lines=lines+line+'\n'
				#print row['Project']
				#print sep.join(row.values())+'\n'
				
#	print lines
#	print headers
	
	#file.write(headers+'\n')
	#file.write(lines)
	print("done!")
main()