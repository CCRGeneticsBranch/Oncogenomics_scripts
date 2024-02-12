<?php

$d=dirname(__FILE__);
$config=include "$d/../../config/database.php";

$connection = $config["connections"][$config["default"]];

print($connection["host"]."\t".$connection["database"]."\t".$connection["username"]."\t".$connection["password"]."\t".$connection["port"]);

?>
