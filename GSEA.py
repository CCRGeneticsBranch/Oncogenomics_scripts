#!/usr/bin/env python

import os, glob, operator, random, time, subprocess
from multiprocessing import Process, Pool
import multiprocessing
import smtplib
import fnmatch, re
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import sys, json
import time
from email.mime.application import MIMEApplication
from email import encoders
from email.mime.base import MIMEBase
def composeMail(recipients,message,files=[]):
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

def get_message(intro,product_name,admin_email,link):
	timestamp= time.strftime("%x")
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


def run_PreRanked(params):
	gset_path=params["gset_path"]
	gset=gset_path.rsplit('/', 1)[-1]
	print(gset_path)
	try:
		print("in run_Preranked")
		form_input=params["form_input"]

		gset_path=params["gset_path"]
		gset=gset_path.rsplit('/', 1)[-1]
		print(gset)
		print(params["project_id"])
		project_id=params["project_id"]
		rank_path=params["in_path"]
		input_file=rank_path.rsplit('/', 1)[-1]

		
		print(input_file)
		print(params["sample_id"])
		print(params["sample_name"])
		out_path=params["out_path"]

		if out_path.find('-') > -1:
			out_tmp=out_path.replace("-",'_')
			rank_tmp=rank_path.replace("-",'_')
			tmp_path=os.path.basename(os.path.dirname(out_path))
			nodash_path=os.path.dirname(out_tmp)
			print("nodash_path=" + nodash_path)
			if not os.path.exists(nodash_path):
				print ("making symlink ln -s tmp_path nodash_path")
				os.system("ln -s " + tmp_path  + " " + nodash_path)
			print ("renaming" + out_path + " to " + out_tmp)
			out_path=out_tmp
			print ("renaming" + rank_path + " to " + rank_tmp)
			rank_path=rank_tmp
		
		token_id=params["token_id"]
		email=params["email"]
		url=params["url"]
		norm=form_input["norm"];
		scoring_scheme=form_input["scoring_scheme"]
		rpt_label= form_input["rpt_label"]
		rpt_label=rpt_label.replace(" ","_")
		create_svgs= form_input["create_svgs"]
		make_sets= form_input["make_sets"]
		plot_top_x= form_input["plot_top_x"] 
		rnd_seed =form_input["rnd_seed"] 
		set_max =form_input["set_max"] 
		set_min =form_input["set_min"] 
		zip_report ="true"
		gui =form_input["gui"]
		normal_project_name=params["normal_project_name"]
		print (normal_project_name)
		rank_by =form_input["rank_by"]
		out_name=rpt_label+"_"+str(token_id)
		link=url
		directory=params["directory"];
		cmd1="java -cp ../app/bin/gsea-3.0.jar xtools.gsea.GseaPreranked -gmx "+ gset_path+ " -norm "+ norm+ " -rnk "+ rank_path+ " -scoring_scheme "+ scoring_scheme+ " -rpt_label "+ out_name+ " -create_svgs "+ create_svgs+ " -make_sets "+ make_sets +" -plot_top_x "+ plot_top_x+ " -rnd_seed "+ rnd_seed+ " -set_max "+ set_max+ " -set_min "+ set_min+ " -zip_report "+ zip_report+ " -out "+ out_path+ " -gui "+ gui	
		sample_id=params["sample_id"]
		patient_id=params["patient_id"]
		case_id=params["case_id"]
		user_id=params["user_id"]
		sample_name=params["sample_name"]
		ispublic=params["ispublic"]
		form_input=json.dumps(form_input)
		form_input= '"%s"'%form_input
		print form_input 
		os.system("qsub -v command='"+cmd1+"',directory='"+directory+"',sample_id='"+sample_id+"',input_file='"+input_file+"',input_file='"+input_file+"',token_id='"+token_id+"',case_id='"+case_id+"',out_name='"+out_name+"',gset='"+gset+"',sample_name='"+sample_name+"',user_id='"+user_id+"',url='"+url+"',out_path='"+out_path+"',email='"+email+"',patient_id='"+patient_id+"',rank_by='"+rank_by+"',ispublic='"+ispublic+"',form_input='"+form_input+"',normal_project_name='"+normal_project_name+"',project_id='"+project_id+"' ../app/scripts/backend/submit_GSEA.pbs" )

#		subprocess.call(['java', '-cp', '../app/bin/gsea-3.0.jar', 'xtools.gsea.GseaPreranked', '-gmx', gset_path, '-norm', norm, '-rnk', rank_path, '-scoring_scheme', scoring_scheme, '-rpt_label', out_name, '-create_svgs', create_svgs, '-make_sets', make_sets ,'-plot_top_x', plot_top_x, '- rnd_seed', rnd_seed, '-set_max', set_max, '-set_min', set_min, '-zip_report', zip_report, '-out', out_path, '-gui', gui])

#		dirs= os.walk(out_path).next()[1]
#		regex=re.compile(out_name)
#		for item in dirs:
#			if item.startswith(out_name):
#				os.rename(out_path+'/'+item,out_path+'/'+out_name) 
#				os.system(' cd '+out_path+'/'+out_name+'; tar -cf ../'+out_name+'.tar *')
#				os.system(' cd '+out_path+'/'+out_name+'; zip ../'+out_name+'.zip *')
#				message=get_message("Here are the results you requested on ","GSEA","oncogenomics@mail.nih.gov",link)
#				composeMail(email,message,[out_path+'/'+out_name+'.zip',out_path+'/'+out_name+'.tar'])
#				subprocess.call(['perl', '../app/scripts/backend/gsea_insert.pl','-i',input_file,'-s',params["sample_id"],'-t',token_id,'-p',params["patient_id"],'-c',params["case_id"],'-o',out_name,'-g',gset,'-u',params["user_id"],'-n',params["sample_name"]])
#				sys.exit();
#		print ("emailing error message")
#		message=get_message("An error occured during calculation on ", "GSEA","oncogenomics@mail.nih.gov",link)
#		composeMail(email,message,[])
	except Exception as e:
		print (e)


if __name__ == '__main__' :
	print("In GSEA script")
	try:
		params=json.loads(sys.argv[1])
		if params["form_input"]["type"]=='Pre_ranked':
			run_PreRanked(params)
	except Exception as e: print(e)