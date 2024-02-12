<?php

//example: 
//php app/scripts/backend/getGeneFusionData.php left_gene=PAX5 right_gene=ZNF521 left_junction=36882001 right_junction=22807661 sample_id=Sample_CL0035_T1R_T_HWHT3BGXX url=https://fsabcl-onc01d.ncifcrf.gov/clinomics/public
//php app/scripts/backend/getGeneFusionData.php left_gene=PAX3 right_gene=FOXO1 left_junction=223084859 right_junction=41134997 sample_id=Sample_NCI0064tumor2_T_H145DBGXX url=https://fsabcl-onc01d.ncifcrf.gov/clinomics/public


parse_str(implode('&', array_slice($argv, 1)), $input);

$left_gene = $input["left_gene"];
$right_gene = $input["right_gene"];
$left_chr = $input["left_chr"];
$right_chr = $input["right_chr"];
$left_junction = $input["left_junction"];
$right_junction = $input["right_junction"];
$url = $input["url"];
$url_trans = "$url/calculateGeneFusionData/$left_gene/$right_gene/$left_chr/$right_chr/$left_junction/$right_junction";
#print $url_trans;
$res = getResponse($url_trans);
print $res;

/*
$trans_json = json_decode($res);
if (is_object($trans_json)) {
    if (property_exists($trans_json, $left_gene) && property_exists($trans_json, $right_gene)) {
        $left_trans_list = $trans_json->{$left_gene};
        $right_trans_list = $trans_json->{$right_gene};

        foreach ($left_trans_list as $left_trans_obj) {
            foreach ($right_trans_list as $right_trans_obj) {
                $left_trans = $left_trans_obj->{'trans'};
                $right_trans = $right_trans_obj->{'trans'};
                $left_trans_exp = $left_trans_obj->{'exp'};
                $right_trans_exp = $right_trans_obj->{'exp'};
                $url_fusion = "$url/calculateGeneFusionData/$left_gene/$left_trans/$right_gene/$right_trans/$left_junction/$right_junction";
                //print $url_fusion;
                $res = getResponse($url_fusion);
                $fusion_json = json_decode($res);
                if (is_object($fusion_json) && property_exists($fusion_json, 'type')) {
                    print "$sample_id\t$left_gene\t$left_trans\t$left_trans_exp\t$right_gene\t$right_trans\t$right_trans_exp\t$fusion_json->type\t$fusion_json->left_cancer_gene\t$fusion_json->right_cancer_gene\t$res\n";
                }            
            }
        }
    }
}
*/
//$response = \Httpful\Request::get($url)->expectsJson()->send();

function getResponse($url) {
    $curl = curl_init($url);
    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 0);
    $curl_response = curl_exec($curl);
    if ($curl_response === false) {        
        $curl_response = "Error:".curl_error($curl);
    }    
    curl_close ($curl);
    return $curl_response;
}

?>