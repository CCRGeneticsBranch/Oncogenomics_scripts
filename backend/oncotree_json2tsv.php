<?php

parse_str(implode('&', array_slice($argv, 1)), $input);

$input = file_get_contents($input["in"]);

$jsons = json_decode($input);

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