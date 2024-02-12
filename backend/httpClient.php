<?php

parse_str(implode('&', array_slice($argv, 1)), $input);

$url = $input["url"];
$res = getResponse($url);
print $res;

function getResponse($url) {
    $curl = curl_init($url);
    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 0);
    $curl_response = curl_exec($curl);
    curl_close ($curl);
    return $curl_response;
}

?>