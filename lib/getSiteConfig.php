<?php

$key=$argv[1];

$d=dirname(__FILE__);
$config=include "$d/../../config/site.php";

if (array_key_exists($key, $config)) {
	$value = $config[$key];
	print($value);
} else {
	print("$key not found");
}




?>
