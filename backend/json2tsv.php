<?php

parse_str(implode('&', array_slice($argv, 1)), $input);

$input = file_get_contents($input["in"]);

$jsons = json_decode($input);

/*
switch (json_last_error()) {
        case JSON_ERROR_NONE:
            echo ' - No errors';
        break;
        case JSON_ERROR_DEPTH:
            echo ' - Maximum stack depth exceeded';
        break;
        case JSON_ERROR_STATE_MISMATCH:
            echo ' - Underflow or the modes mismatch';
        break;
        case JSON_ERROR_CTRL_CHAR:
            echo ' - Unexpected control character found';
        break;
        case JSON_ERROR_SYNTAX:
            echo ' - Syntax error, malformed JSON';
        break;
        case JSON_ERROR_UTF8:
            echo ' - Malformed UTF-8 characters, possibly incorrectly encoded';
        break;
        default:
            echo ' - Unknown error';
        break;
}

echo count($jsons);
exit;
*/
$first = true;
$headers = array();
foreach ($jsons as $json) {
	$json = (array)$json;
	if ($first) {
		$headers = array_keys($json);
		print implode("\t", $headers)."\n";
		$first = false;	
	}
	$values = array();	
	foreach ($headers as $header) {
		$value = $json[$header];
		if ($value == null)
			$value = "";
		$value = str_replace("\r", " ",$value);
		$value = str_replace("\n", " ",$value);
		$values[] = $value;		
	}
	print implode("\t", $values)."\n";
}

?>