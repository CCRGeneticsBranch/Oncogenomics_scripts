<?php

parse_str(implode('&', array_slice($argv, 1)), $input);

$content = file_get_contents($input["in"]);
$lines = explode("\n", $content);

$result = [
    "headers" => ["chromosome", "bp_start", "bp_stop", "band", "stain"],
    "cytoband_data" => []
];

foreach ($lines as $line) {
    $cols = preg_split('/\t+/', trim($line));
    if (count($cols) >= 5) {
        $result["cytoband_data"][] = [
            $cols[0],
            $cols[1],
            $cols[2],
            $cols[3],
            $cols[4]
        ];
    }
}

header('Content-Type: application/json');
echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);