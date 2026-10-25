<?php
$path = '/usr/src/opencart/admin/controller/marketplace/modification.php';
$source = file_get_contents($path);

if ($source === false) {
	fwrite(STDERR, "modification.php was not found\n");
	exit(1);
}

$refresh = "editSettingValue('config', 'config_maintenance', \$maintenance);";
$reset = "\n\t\t\tif (function_exists('opcache_reset')) {\n\t\t\t\topcache_reset();\n\t\t\t}";

if (substr_count($source, $refresh) !== 1) {
	fwrite(STDERR, "modification refresh anchor was not found\n");
	exit(1);
}

$source = str_replace($refresh, $refresh . $reset, $source);

$clear = "rmdir(\$file);\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\n\t\t\t\$this->session->data['success'] = \$this->language->get('text_success');";
$clear_reset = "rmdir(\$file);\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\n\t\t\tif (function_exists('opcache_reset')) {\n\t\t\t\topcache_reset();\n\t\t\t}\n\n\t\t\t\$this->session->data['success'] = \$this->language->get('text_success');";

if (substr_count($source, $clear) !== 1) {
	fwrite(STDERR, "modification clear anchor was not found\n");
	exit(1);
}

$source = str_replace($clear, $clear_reset, $source);

if (file_put_contents($path, $source) === false) {
	fwrite(STDERR, "modification.php could not be updated\n");
	exit(1);
}
