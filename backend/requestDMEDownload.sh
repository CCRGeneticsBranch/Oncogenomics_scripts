#!/bin/bash
dest=chouh@helix.nih.gov:/data/khanlab/projects/DME_download_request/
script_dir=`dirname "$0"`
src=${script_dir}/../../../storage/DME_download_request
if [ "$(ls -A $src)" ];then 
	#echo "no empty";
	scp -p $src/* $dest
	#echo "scp -p $src/* $dest"
	rm $src/*
fi
