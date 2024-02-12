<?php

parse_str(implode('&', array_slice($argv, 1)), $input);

$app_path = $input["app_path"];
$in_file = $input["in_file"];
$res = predictPfamDomain($app_path, $in_file);
print json_encode($res);

function compareDomains($a, $b) {
    return ($a[0] > $b[0]);
}

function predictPfamDomain($app_path, $in_file) {
        //$pep_file = tempnam(sys_get_temp_dir() , "");
        $out_file = tempnam(sys_get_temp_dir() , "");
        $sorted_out_file = tempnam(sys_get_temp_dir() , "");        
        //$handle = fopen($pep_file, "w");
        //fwrite($handle,$seq);
        //fclose($handle);
        //$cmd = app_path()."/scripts/predictPfamDomain.sh $pep_file $out_file";        

        $cmd = $app_path."/bin/hmmer/binaries/hmmscan --domtblout $out_file -E 1e-5 --domE 1e-5 ".$app_path."/bin/hmmer/pfam/Pfam-A.hmm $in_file";
        $ret = exec($cmd);
        $cmd = "cat $out_file | grep -v '^#' | sed 's/\s\+/ /g' | cut -d' ' -f1,2,23-";
        $ret = exec($cmd, $domain_descs);
        $descs = array();
        $accs = array();
        foreach ($domain_descs as $demain_desc) {
            $fields = preg_split('/\s/', $demain_desc);
            $descs[$fields[0]] = implode(' ', array_slice($fields, 2));
            $accs[$fields[0]] = $fields[1]; 
        }

        $ret = exec("cat $out_file | grep -v '^#' | awk '{print $1,$3,$4,$6,$7,$13,$16,$17,$18,$19}' | sed 's/ /\t/g' | sort -k 3,3 -k 6n > $sorted_out_file");     
        $domains = array();
        foreach(file($sorted_out_file) as $line) {
            if (substr($line, 0, 1) == "#")
                continue;
            $fields = preg_split('/\t/', $line);
            $domains[$fields[2]][] = array($fields[8], $fields[9], $fields[0], $fields[6], $descs[$fields[0]], $accs[$fields[0]]);
        }
        //return $domains;
        $filtered_domains = array();
        foreach ($domains as $gene=>$domain) {
            $selected_domains = array();
            for ($i=0;$i<count($domain);$i++) {
                $d1 = $domain[$i];               
                $s1 = (int)$d1[0];
                $e1 = (int)$d1[1];
                $name = $d1[2];
                $evalue = $d1[3];
                $desc = $d1[4];
                $acc = $d1[5];
                $len1 = $e1 - $s1;
                $overlapped = false;
                for ($j=0;$j<count($selected_domains);$j++) {
                    $d2 = $selected_domains[$j];
                    $s2 = (int)$d2[0];
                    $e2 = (int)$d2[1];                  
                    $len2 = $e2 - $s2;
                    $len = min($len1, $len2);   
                    if (($e1 > $s2) && ($e2 > $s1)) {
                        if ($s1 >= $s2 && (($e2 - $s1) / $len) > 0.1) {
                            $overlapped = true;
                            break;
                        }
                        if ($s2 >= $s1 && (($e1 - $s2) / $len) > 0.1) {
                            $overlapped = true;
                            break;
                        }                       
                    }                   
                }
                if (!$overlapped)
                    $selected_domains[] = $d1;
            }
            usort($selected_domains, "compareDomains");
            for ($i=0;$i<count($selected_domains);$i++) {
                $d1 = $selected_domains[$i];                 
                $s1 = $d1[0];
                $e1 = $d1[1];
                $name = $d1[2];
                $evalue = $d1[3];
                $desc = $d1[4];
                $acc = $d1[5];
                $len1 = $e1 - $s1;
                $filtered_domains[$gene][] = array("start_pos" => $s1, "end_pos" => $e1, "name" => $name, "hint" => array("Name" => $name, "Coordinate" => "$s1 - $e1", "Length" => $e1-$s1+1, "Description" => $desc, "Accession" => "<a target=_blank href=http://pfam.xfam.org/family/$acc>$acc</a>"));              
            }
        }
        //Log::info(json_encode($filtered_domains));
        unlink($in_file);
        unlink($out_file);
        unlink($sorted_out_file);
        if (count($filtered_domains) == 0)
            return $filtered_domains;
        return array_values($filtered_domains)[0];

        $cmd = "$app_path/bin/hmmer/binaries/hmmscan --domtblout $out_file -E 1e-5 --domE 1e-5 $app_path/bin/hmmer/pfam/Pfam-A.hmm $in_file";
        $ret = exec($cmd);
        #$cmd = "cat $out_file | grep -v '^#' | sed 's/\s\+/ /g' | cut -d' ' -f1,2,23-";
        $cmd = "cat $out_file | grep -v '^#' | sed 's/\s\+/ /g'";
        $ret = exec($cmd, $domain_data);
        $domains = array();
        foreach ($domain_data as $demain) {
            $fields = preg_split('/\s/', $demain);
            $domains[] = $fields;
        }
        return json_encode($domains);
        /*
        foreach ($domain_descs as $demain_desc) {
            $fields = preg_split('/\s/', $demain_desc);
            $descs[$fields[0]] = implode(' ', array_slice($fields, 2));
            $accs[$fields[0]] = $fields[1]; 
        }
        */

        $ret = exec("$app_path/bin/hmmscan-parser.sh $out_file | sort -k 9n > $sorted_out_file");
        #Log::info("\n".file_get_contents($sorted_out_file));
        //$ret = exec("sed -i 's/ \+/ /g' $out_file");
        //$ret = exec("grep -v '#' $out_file | sort -n -t ' ' -k 20 > $sorted_out_file");
        //echo $sorted_out_file;
        $domains = array();
        foreach(file($sorted_out_file) as $line) {
            if (substr($line, 0, 1) == "#")
                continue;
            $fields = preg_split('/\t/', $line);
            //$desc = implode(' ', array_slice($fields, 22));
            //$desc = 'desc';
            //$domains[$fields[3]][] = array($fields[19], $fields[20], $fields[0], $fields[6],$desc, $fields[1]);
            $domains[$fields[2]][] = array($fields[8], $fields[9], $fields[0], $fields[6], $descs[$fields[0]], $accs[$fields[0]]);
        }
        //return $domains;
        $filtered_domains = array();
        foreach ($domains as $gene=>$domain) {
            for ($i=0;$i<count($domain);$i++) {
                $d1 = $domain[$i];               
                $s1 = $d1[0];
                $e1 = $d1[1];
                $name = $d1[2];
                $evalue = $d1[3];
                $desc = $d1[4];
                $acc = $d1[5];
                $len1 = $e1 - $s1;
                $overlapped = false;
                for ($j=0;$j<count($domain);$j++) {
                    if ($i == $j)
                        continue;
                    $d2 = $domain[$j];
                    $s2 = $d2[0];
                    $e2 = $d2[1];                   
                    $len2 = $e2 - $s2;
                    $len = min($len1, $len2);   
                    //echo "s1: $s1<BR>e1: $e1<BR>s2: $s2<BR>e2: $e2<BR>evalue2: $evalue2<BR>";         

                    
                    if ($s2 < $s1 and $e2 >$e1) {
                        $overlapped = true;
                        break;
                    }
                    
                    
                    if ($s2 >= $s1 and $s2 <=$e1) {
                        //echo "s1: $s1<BR>e1: $e1<BR>s2: $s2<BR>e2: $e2<BR>len1: $len1<BR>len2:$len2<BR>pct".(($e1 - $s2) / $len)."<BR>";
                        if (($e1 - $s2) / $len > 0.2 && $len1 <= $len2) {
                            
                            $overlapped = true;
                            break;
                        }
                    }
                    if ($s1 >= $s2 and $s1 <=$e2 ) {
                        //echo "pct".(($e2 - $s1) / $len)."<BR>";
                        if (($e2 - $s1) / $len > 0.2 && $len1 <= $len2) {                           
                            $overlapped = true;
                            break;
                        }                   
                    }
                }
                //if (!$overlapped)
                    //$filtered_domains[$gene][] = array($s1, $e1, $name);
                    $filtered_domains[$gene][] = array("start_pos" => $s1, "end_pos" => $e1, "name" => $name, "hint" => array("Name" => $name, "Coordinate" => "$s1 - $e1", "Length" => $e1-$s1+1, "Description" => $desc, "Accession" => "<a target=_blank href=http://pfam.xfam.org/family/$acc>$acc</a>"));
            }
        }
        //unlink($in_file);
        unlink($out_file);
        unlink($sorted_out_file);
        return $filtered_domains;
    }

?>