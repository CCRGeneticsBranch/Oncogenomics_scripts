#!/usr/bin/env python

import os, glob, operator, random, time, subprocess
from multiprocessing import Process, Pool
import multiprocessing
import smtplib
import fnmatch, re
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import sys, json,getopt
import time
from email.mime.application import MIMEApplication
from email import encoders
from email.mime.base import MIMEBase



def main(argv):
	try:
		input_file=''
		token_id=''
		case_id=''
		out_name=''
		gset=''
		user_id=''
		sample_name=''
		sample_id=''
		url=''
		out_path=''
		email=''
		patient_id=''
		rank_by=''
		ispublic=''
		form_input=''
		normal_project_name=''
		project_id=''
		opts, args = getopt.getopt(argv,"s:i:t:c:o:g:u:n:l:p:e:a:r:b:m:z:")
		for opt, arg in opts:
			if opt in ("-s"):
				sample_id = arg
			elif opt in ("-i"):
				input_file = arg
			elif opt in ("-t"):
				token_id = arg
			elif opt in ("-c"):
				case_id = arg
			elif opt in ("-o"):
				out_name = arg
			elif opt in ("-g"):
				gset = arg
			elif opt in ("-u"):
				user_id = arg
			elif opt in ("-n"):
				sample_name = arg
			elif opt in ("-l"):
				url = arg
			elif opt in ("-p"):
				out_path = arg
			elif opt in ("-e"):
				email = arg
			elif opt in ("-a"):
				patient_id = arg
			elif opt in ("-r"):
				rank_by = arg
			elif opt in ("-b"):
				ispublic = arg
			elif opt in ("-m"):
				normal_project_name = arg
			elif opt in ("-z"):
				project_id = arg
		print opts

		Send_email(input_file,token_id,case_id,out_name,gset,user_id,sample_name,sample_id,url,out_path,email,patient_id,rank_by,ispublic,normal_project_name,project_id)
	except Exception as e:
		print (e)

def composeMail(recipients,message,files=[]):
	try:
		print("Emailing")
		packet = MIMEMultipart()
		packet = MIMEMultipart('alternative')
		packet['Subject'] = 'GSEA Job done: '
		packet['From'] = "oncogenomics@mail.nih.gov"
		packet['To'] = recipients
		packet.attach(MIMEText(message,'html'))
		print files
		for file in files:
				comp = open(file,'rb')
				part = MIMEBase('application', "octet-stream")
				part.set_payload(comp.read())
				encoders.encode_base64(part)
				Name=os.path.basename(file)
				part.add_header('Content-Disposition', 'attachment; filename='+Name)
				packet.attach(part)

		smtp  = smtplib.SMTP('mailfwd.nih.gov')
		smtp.sendmail("mailfwd.nih.gov",recipients,packet.as_string())
		return ("SENT MAIL")
	except Exception as e: print(e)
def get_message(intro,product_name,admin_email,link,timestamp):
	print "Here is the Link to the past:"
	header = """<h2>"""+product_name+"""</h2>"""
	body = """
        <div style="background-color:white;border-top:25px solid #142830;border-left:2px solid #142830;border-right:2px solid #142830;border-bottom:2px solid #142830;padding:20px">
            Hello,<br>
            <p>"""+intro+""" """+timestamp+""" from  """+product_name+""".</p>
            <p>
            <div style="margin:20px auto 40px auto;width:200px;text-align:center;font-size:14px;font-weight:bold;padding:10px;line-height:25px">
                <div style="font-size:24px;"><a href='"""+link+"""'>View Results</a></div>
            </div>
            </p>
            <p>The results will be available online for the next 30 days.</p>
        </div>
        """
	footer = """
          <div>
            <p>
              (Note:  Please do not reply to this email. If you need assistance, please contact """+admin_email+""")
            </p>
          </div>
            <div style="background-color:#ffffff;color:#888888;font-size:13px;line-height:17px;font-family:sans-serif;text-align:left">
                  <p>
                    <strong>About <em>"""+product_name+"""</em></strong></em><br>
                    Gene Set Enrichment Analysis (GSEA) is a computational method that determines whether an a priori defined set of genes shows statistically significant, concordant differences between two biological states (e.g. phenotypes).                   <br>
                      <br>
                      
                      <strong>For more information, visit
                        <a target="_blank" style="color:#888888" href="http://software.broadinstitute.org/gsea/</a>
                      </strong>
                  </p>
                  <p style="font-size:11px;color:#b0b0b0">If you did not request a calculation please ignore this email.
    Your privacy is important to us.  Please review our <a target="_blank" style="color:#b0b0b0" href="http://www.cancer.gov/policies/privacy-security">Privacy and Security Policy</a>.
    </p>
                  
                </div>
                """
	message = """
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>html title</title>
      </head>
      <body>"""+header+body+footer+"""</body>"""

	return (message)


def Send_email(input_file,token_id,case_id,out_name,gset,user_id,sample_name,sample_id,url,out_path,email,patient_id,rank_by,ispublic,normal_project_name,project_id):
	print("Zipping")
	try:
		timestamp= time.strftime("%x")
		dirs= os.walk(out_path).next()[1]
		regex=re.compile(out_name)
		for item in dirs:
			if item.startswith(out_name):
				os.rename(out_path+'/'+item,out_path+'/'+out_name) 
				os.system(' cd '+out_path+'/'+out_name+'; tar -cf ../'+out_name+'.tar *')
				os.system(' cd '+out_path+'/'+out_name+'; zip ../'+out_name+'.zip *')
				message=get_message("Here are the results you requested on ","GSEA","oncogenomics@mail.nih.gov",url,timestamp)
				composeMail(email,message,[out_path+'/'+out_name+'.zip',out_path+'/'+out_name+'.tar'])
				subprocess.call(['/opt/nasapps/development/perl/5.16.2/bin/perl', '../app/scripts/backend/gsea_insert.pl','-i',input_file,'-s',sample_id,'-t',token_id,'-p',patient_id,'-c',case_id,'-o',out_name,'-g',gset,'-u',user_id,'-n',sample_name,'-r',rank_by,'-b',ispublic,'-j',out_path,'-m',normal_project_name,'-a',timestamp,'-z',project_id])
				sys.exit();
		print ("emailing error message")
		message=get_message("An error occured during calculation on ", "GSEA","oncogenomics@mail.nih.gov",url,timestamp)
		composeMail(email,message,[])
	except Exception as e:
		print (e)

if __name__ == "__main__":
	try:
		print ("Zipping and emailing")
		main(sys.argv[1:])
	except Exception as e: print(e)