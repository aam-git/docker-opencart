#!/usr/bin/env php
<?php
/**
 * OpenCart 3.0.5.1 container maintenance.
 *
 * Reads an existing config.php without rewriting it, and upgrades the
 * database once. Credentials and DIR_STORAGE stay as the shop saved them.
 */

const OPENCART_VERSION = '3.0.5.1';
const HTML_ROOT = '/var/www/html/';
const CONFIG_FILE = HTML_ROOT . 'config.php';
const MARKER_KEY = 'config_docker_opencart_version';

function fail(string $message, int $code = 1): void
{
    fwrite(STDERR, $message . PHP_EOL);
    exit($code);
}

function warn(string $message): void
{
    fwrite(STDERR, 'WARNING: ' . $message . PHP_EOL);
}

function config_define_names(): array
{
    return [
        'DB_DRIVER',
        'DB_HOSTNAME',
        'DB_USERNAME',
        'DB_PASSWORD',
        'DB_DATABASE',
        'DB_PORT',
        'DB_PREFIX',
        'DIR_SYSTEM',
        'DIR_STORAGE',
        'DIR_IMAGE',
    ];
}

function load_store_config(): void
{
    if (!is_file(CONFIG_FILE)) {
        return;
    }

    $allowed = array_flip(config_define_names());
    $lines = file(CONFIG_FILE, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        fail('Could not read ' . CONFIG_FILE);
    }

    foreach ($lines as $line) {
        if (!preg_match('/define\\s*\\(\\s*[\'"]([A-Z0-9_]+)[\'"]/', $line, $match)) {
            continue;
        }
        if (!isset($allowed[$match[1]]) || defined($match[1])) {
            continue;
        }
        eval($line);
    }
}

function db_value(string $name, ?string $env = null, string $default = ''): string
{
    if (defined($name)) {
        return (string) constant($name);
    }
    if ($env !== null && getenv($env) !== false) {
        return (string) getenv($env);
    }
    return $default;
}

function store_configured(): bool
{
    load_store_config();
    return db_value('DB_HOSTNAME') !== '' && db_value('DB_USERNAME') !== '';
}

function connection_settings(): array
{
    load_store_config();

    $prefix = db_value('DB_PREFIX', 'DB_PREFIX', 'oc_');
    if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
        fail('Refusing database prefix that is not alphanumeric');
    }

    return [
        'driver' => db_value('DB_DRIVER', 'DB_DRIVER', 'mysqli'),
        'hostname' => db_value('DB_HOSTNAME', 'DB_HOSTNAME', 'mysql'),
        'username' => db_value('DB_USERNAME', 'DB_USERNAME', 'root'),
        'password' => db_value('DB_PASSWORD', 'DB_PASSWORD', ''),
        'database' => db_value('DB_DATABASE', 'DB_DATABASE', ''),
        'port' => (int) db_value('DB_PORT', 'DB_PORT', '3306'),
        'prefix' => $prefix,
    ];
}

function storage_path(): string
{
    load_store_config();
    $path = HTML_ROOT . 'system/storage/';
    if (defined('DIR_STORAGE') && DIR_STORAGE !== '') {
        $path = rtrim(DIR_STORAGE, '/') . '/';
    }
    // Live stacks keep storage under the /var/www volume. Refuse anything else
    // so a bad config cannot redirect chown or the database dump.
    if (!str_starts_with($path, '/var/www/')) {
        return HTML_ROOT . 'system/storage/';
    }
    return $path;
}

function connect(array $settings, bool $selectDatabase): mysqli
{
    $database = $selectDatabase ? $settings['database'] : '';
    mysqli_report(MYSQLI_REPORT_OFF);
    $link = @new mysqli(
        $settings['hostname'],
        $settings['username'],
        $settings['password'],
        $database,
        $settings['port']
    );
    if ($link->connect_errno) {
        throw new RuntimeException($link->connect_error ?: 'Database connection failed');
    }
    $link->set_charset('utf8mb4');
    return $link;
}

function export_env(string $path): void
{
    if (!store_configured()) {
        fail('config.php has no database hostname and username');
    }

    $settings = connection_settings();
    $lines = [
        'DB_DRIVER=' . escapeshellarg($settings['driver']),
        'DB_HOSTNAME=' . escapeshellarg($settings['hostname']),
        'DB_USERNAME=' . escapeshellarg($settings['username']),
        'DB_PASSWORD=' . escapeshellarg($settings['password']),
        'DB_DATABASE=' . escapeshellarg($settings['database']),
        'DB_PORT=' . escapeshellarg((string) $settings['port']),
        'DB_PREFIX=' . escapeshellarg($settings['prefix']),
        'DIR_STORAGE=' . escapeshellarg(storage_path()),
    ];
    if (file_put_contents($path, implode(PHP_EOL, $lines) . PHP_EOL) === false) {
        fail('Could not write ' . $path);
    }
    chmod($path, 0600);
}

function tables_exist(): bool
{
    $settings = connection_settings();
    if ($settings['database'] === '' || $settings['hostname'] === '' || $settings['username'] === '') {
        return false;
    }

    try {
        $link = connect($settings, true);
    } catch (Throwable $exception) {
        return false;
    }

    $table = $settings['prefix'] . 'user';
    $sql = "SHOW TABLES LIKE '" . $link->real_escape_string($table) . "'";
    $result = $link->query($sql);
    $found = $result instanceof mysqli_result && $result->num_rows > 0;
    $link->close();
    return $found;
}

function marker_value(mysqli $link, string $prefix): string
{
    $table = '`' . $prefix . 'setting`';
    $key = $link->real_escape_string(MARKER_KEY);
    $sql = "SELECT `value` FROM {$table} WHERE `key` = '{$key}' AND `code` = 'config' ORDER BY setting_id DESC LIMIT 1";
    $result = $link->query($sql);
    if (!$result instanceof mysqli_result || $result->num_rows < 1) {
        return '';
    }
    $row = $result->fetch_assoc();
    return isset($row['value']) ? (string) $row['value'] : '';
}

function write_marker(mysqli $link, string $prefix): void
{
    $table = '`' . $prefix . 'setting`';
    $key = $link->real_escape_string(MARKER_KEY);
    $version = $link->real_escape_string(OPENCART_VERSION);
    $link->query("DELETE FROM {$table} WHERE `key` = '{$key}'");
    $insert = "INSERT INTO {$table} SET `store_id` = '0', `code` = 'config', `key` = '{$key}', `value` = '{$version}', `serialized` = '0'";
    if (!$link->query($insert)) {
        fail('Could not record the upgrade version: ' . $link->error);
    }
}

function quiet_incompatible_extensions(): void
{
    $settings = connection_settings();
    if ($settings['database'] === '') {
        fail('Database name is missing from config.php');
    }
    try {
        $link = connect($settings, true);
    } catch (Throwable $exception) {
        fail('Database connection failed: ' . $exception->getMessage());
    }

    $prefix = $settings['prefix'];
    $table = '`' . $prefix . 'setting`';
    $quietKey = 'config_docker_opencart_extensions_quieted';
    $escapedQuiet = $link->real_escape_string($quietKey);
    $already = $link->query("SELECT `value` FROM {$table} WHERE `key` = '{$escapedQuiet}' AND `code` = 'config' LIMIT 1");
    if ($already instanceof mysqli_result && $already->num_rows > 0) {
        $link->close();
        return;
    }

    $like = "analytics\\_%\\_status";
    $keep = 'analytics_google_analytics_status';
    $found = $link->query(
        "SELECT `key` FROM {$table} WHERE `key` LIKE '{$like}' AND `key` != '{$keep}' AND `value` != '0'"
    );
    if ($found instanceof mysqli_result) {
        while ($row = $found->fetch_assoc()) {
            fwrite(STDOUT, 'Switched off ' . $row['key'] . PHP_EOL);
        }
    }
    if (!$link->query(
        "UPDATE {$table} SET `value` = '0' WHERE `key` LIKE '{$like}' AND `key` != '{$keep}' AND `value` != '0'"
    )) {
        fail('Could not switch off third-party analytics extensions: ' . $link->error);
    }

    $insert = "INSERT INTO {$table} SET `store_id` = '0', `code` = 'config', `key` = '{$escapedQuiet}', `value` = '1', `serialized` = '0'";
    if (!$link->query($insert)) {
        fail('Could not record the extension check: ' . $link->error);
    }
    $link->close();
}

function modification_snapshot_file(): string
{
    return storage_path() . '.docker-enabled-modifications';
}

function read_modification_snapshot(): array
{
    $file = modification_snapshot_file();
    if (!is_file($file)) {
        return [];
    }
    $decoded = json_decode((string) file_get_contents($file), true);
    if (!is_array($decoded)) {
        return [];
    }
    $rows = [];
    foreach ($decoded as $row) {
        if (!is_array($row) || !isset($row['id'])) {
            continue;
        }
        $rows[] = [
            'id' => (int) $row['id'],
            'name' => isset($row['name']) ? (string) $row['name'] : '',
        ];
    }
    return $rows;
}

function pause_enabled_modifications(mysqli $link, string $prefix): void
{
    $exists = $link->query("SHOW TABLES LIKE '" . $link->real_escape_string($prefix . 'modification') . "'");
    if (!$exists instanceof mysqli_result || $exists->num_rows < 1) {
        return;
    }

    $modifications = '`' . $prefix . 'modification`';
    $found = $link->query("SELECT `modification_id`, `name` FROM {$modifications} WHERE `status` = 1");
    if (!$found instanceof mysqli_result) {
        fail('Could not read modification records: ' . $link->error);
    }
    $rows = [];
    while ($row = $found->fetch_assoc()) {
        $rows[] = [
            'id' => (int) $row['modification_id'],
            'name' => (string) $row['name'],
        ];
    }
    $encoded = json_encode($rows);
    if ($encoded === false || file_put_contents(modification_snapshot_file(), $encoded) === false) {
        fail('Could not record which modifications are enabled');
    }
    chmod(modification_snapshot_file(), 0640);
    if ($rows === []) {
        fwrite(STDOUT, 'No modifications are enabled' . PHP_EOL);
        return;
    }

    $ids = [];
    foreach ($rows as $row) {
        $ids[] = (string) $row['id'];
    }
    if (!$link->query("UPDATE {$modifications} SET `status` = 0 WHERE `modification_id` IN (" . implode(',', $ids) . ')')) {
        fail('Could not pause modifications: ' . $link->error);
    }
    foreach ($rows as $row) {
        fwrite(STDOUT, 'Paused modification ' . $row['name'] . PHP_EOL);
    }
}

function resume_modifications(?mysqli $link = null, ?string $prefix = null): void
{
    $file = modification_snapshot_file();
    if (!is_file($file)) {
        return;
    }
    $rows = read_modification_snapshot();
    $ownLink = false;
    if (!$link instanceof mysqli) {
        $settings = connection_settings();
        if ($settings['database'] === '') {
            fail('Database name is missing from config.php');
        }
        try {
            $link = connect($settings, true);
        } catch (Throwable $exception) {
            fail('Database connection failed: ' . $exception->getMessage());
        }
        $prefix = $settings['prefix'];
        $ownLink = true;
    }
    if ($rows !== []) {
        $ids = [];
        foreach ($rows as $row) {
            $ids[] = (string) $row['id'];
        }
        $modifications = '`' . $prefix . 'modification`';
        if (!$link->query("UPDATE {$modifications} SET `status` = 1 WHERE `modification_id` IN (" . implode(',', $ids) . ')')) {
            fail('Could not restore modifications: ' . $link->error);
        }
        foreach ($rows as $row) {
            fwrite(STDOUT, 'Restored modification ' . $row['name'] . PHP_EOL);
        }
    }
    unlink($file);
    if ($ownLink) {
        $link->close();
    }
}

function clear_directory(string $directory): void
{
    if (!is_dir($directory)) {
        mkdir($directory, 0775, true);
        return;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($directory, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST
    );
    foreach ($iterator as $item) {
        if ($item->isDir()) {
            rmdir($item->getPathname());
        } else {
            unlink($item->getPathname());
        }
    }
}

function dump_database(array $settings, string $destination): bool
{
    $command = [
        'mysqldump',
        '--host=' . $settings['hostname'],
        '--port=' . $settings['port'],
        '--user=' . $settings['username'],
        '--password=' . $settings['password'],
        '--single-transaction',
        '--quick',
        '--no-tablespaces',
        '--default-character-set=utf8mb4',
        '--routines',
        '--triggers',
        $settings['database'],
    ];

    $pipes = [];
    $process = proc_open($command, [
        1 => ['file', $destination, 'w'],
        2 => ['pipe', 'w'],
    ], $pipes);

    if (!is_resource($process)) {
        warn('Could not start mysqldump. The schema upgrade will continue.');
        return false;
    }

    $error = stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    $status = proc_close($process);
    if ($status !== 0 || !is_file($destination) || filesize($destination) === 0) {
        if (is_file($destination)) {
            unlink($destination);
        }
        $detail = trim((string) $error);
        warn('Database dump failed. The schema upgrade will continue.' . ($detail !== '' ? ' ' . $detail : ''));
        return false;
    }

    return true;
}

function define_install_paths(): void
{
    $storage = storage_path();
    if (!defined('DIR_SYSTEM')) {
        define('DIR_SYSTEM', HTML_ROOT . 'system/');
    }
    if (!defined('DIR_STORAGE')) {
        define('DIR_STORAGE', $storage);
    }
    if (!defined('DIR_OPENCART')) {
        define('DIR_OPENCART', HTML_ROOT);
    }
    if (!defined('DIR_APPLICATION')) {
        define('DIR_APPLICATION', HTML_ROOT . 'install/');
    }
    if (!defined('DIR_IMAGE')) {
        define('DIR_IMAGE', HTML_ROOT . 'image/');
    }
    if (!defined('DIR_LANGUAGE')) {
        define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
    }
    if (!defined('DIR_TEMPLATE')) {
        define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');
    }
    if (!defined('DIR_CONFIG')) {
        define('DIR_CONFIG', DIR_SYSTEM . 'config/');
    }
    if (!defined('DIR_CACHE')) {
        define('DIR_CACHE', $storage . 'cache/');
    }
    if (!defined('DIR_LOGS')) {
        define('DIR_LOGS', $storage . 'logs/');
    }
    // Ignore the shop's compiled modification cache. Those files were built for
    // the old release and can refer to VERSION, which only index.php defines.
    if (!defined('DIR_MODIFICATION')) {
        $upgradeModification = '/tmp/opencart-upgrade-modification/';
        if (!is_dir($upgradeModification)) {
            mkdir($upgradeModification, 0775, true);
        }
        define('DIR_MODIFICATION', $upgradeModification);
    }
    if (!defined('DIR_DOWNLOAD')) {
        define('DIR_DOWNLOAD', $storage . 'download/');
    }
    if (!defined('DIR_SESSION')) {
        define('DIR_SESSION', $storage . 'session/');
    }
    if (!defined('DIR_UPLOAD')) {
        define('DIR_UPLOAD', $storage . 'upload/');
    }
    if (!defined('DIR_DATABASE')) {
        define('DIR_DATABASE', DIR_SYSTEM . 'database/');
    }
    if (!defined('HTTP_SERVER')) {
        define('HTTP_SERVER', 'http://localhost/install/');
    }
    if (!defined('HTTP_CATALOG')) {
        define('HTTP_CATALOG', 'http://localhost/');
    }
    if (!defined('HTTP_OPENCART')) {
        define('HTTP_OPENCART', 'http://localhost/');
    }
}

function config_define_expressions(string $file): array
{
    $lines = file($file, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        return [];
    }

    $expressions = [];
    foreach ($lines as $line) {
        if (preg_match('/define\\s*\\(\\s*[\'"]([A-Z0-9_]+)[\'"]\\s*,\\s*(.+?)\\s*\\)\\s*;/', $line, $match)) {
            $expressions[$match[1]] = $match[2];
        }
    }

    return $expressions;
}

function resolve_config_expression(string $expression, array $expressions, array &$resolved, int $depth = 0): ?string
{
    if ($depth > 8) {
        return null;
    }

    $expression = trim($expression);
    if (preg_match('/^[\'"]([^\'"]*)[\'"]$/', $expression, $match)) {
        return $match[1];
    }

    $parts = preg_split('/\\s*\\.\\s*/', $expression);
    if ($parts === false || $parts === []) {
        return null;
    }

    $value = '';
    foreach ($parts as $part) {
        $part = trim($part);
        if (preg_match('/^[\'"]([^\'"]*)[\'"]$/', $part, $match)) {
            $value .= $match[1];
            continue;
        }
        if (!preg_match('/^[A-Z0-9_]+$/', $part)) {
            return null;
        }
        if (!array_key_exists($part, $resolved)) {
            if (!isset($expressions[$part])) {
                $resolved[$part] = $part === 'DIR_OPENCART' ? HTML_ROOT : null;
            } else {
                $resolved[$part] = resolve_config_expression($expressions[$part], $expressions, $resolved, $depth + 1);
            }
        }
        if ($resolved[$part] === null) {
            return null;
        }
        $value .= $resolved[$part];
    }

    return $value;
}

function config_define_value(string $file, string $name): ?string
{
    $expressions = config_define_expressions($file);
    if (!isset($expressions[$name])) {
        return null;
    }

    $resolved = [];
    return resolve_config_expression($expressions[$name], $expressions, $resolved);
}

function admin_directory(): string
{
    $configs = glob(HTML_ROOT . '*/config.php');
    if ($configs === false) {
        return 'admin';
    }

    $html = realpath(rtrim(HTML_ROOT, '/'));
    $matches = [];
    foreach ($configs as $config) {
        if (config_define_value($config, 'DIR_CATALOG') === null && config_define_value($config, 'HTTP_CATALOG') === null) {
            continue;
        }

        $configFolder = basename(dirname($config));
        if (!preg_match('/^[A-Za-z0-9._-]+$/', $configFolder)) {
            continue;
        }

        $application = config_define_value($config, 'DIR_APPLICATION');
        if ($application === null || $application === '') {
            $folder = $configFolder;
        } else {
            $folder = basename(rtrim($application, '/'));
            if ($folder !== $configFolder) {
                continue;
            }
        }
        if (in_array($folder, ['catalog', 'system', 'image'], true)) {
            continue;
        }

        $realConfigDir = realpath(dirname($config));
        if ($html === false || $realConfigDir === false || dirname($realConfigDir) !== $html) {
            continue;
        }
        if ($application !== null && $application !== '') {
            $realApp = realpath(rtrim($application, '/'));
            if ($realApp === false || $realConfigDir !== $realApp) {
                continue;
            }
        }

        $matches[$folder] = $config;
    }

    if (count($matches) === 1) {
        return (string) array_key_first($matches);
    }
    if (count($matches) > 1) {
        warn('More than one admin config was found. Admin files will be copied to admin/.');
    }

    return 'admin';
}

function shop_config_paths(): array
{
    $paths = [HTML_ROOT . 'config.php'];
    $admin = HTML_ROOT . admin_directory() . '/config.php';
    if (is_file($admin)) {
        $paths[] = $admin;
    }

    return $paths;
}

function snapshot_configs(): array
{
    $copies = [];
    foreach (shop_config_paths() as $path) {
        if (!is_file($path)) {
            continue;
        }
        $copy = tempnam('/tmp', 'opencart-config-');
        if ($copy === false || !copy($path, $copy)) {
            fail('Could not snapshot ' . $path);
        }
        $copies[$path] = $copy;
    }
    return $copies;
}

function restore_configs(array $copies): void
{
    foreach ($copies as $path => $copy) {
        if (!is_file($copy)) {
            continue;
        }
        if (!copy($copy, $path)) {
            warn('Could not restore ' . $path . '. An upgrade model may have changed it.');
        }
        unlink($copy);
    }
}

function report_upgrade_failure(string $model, Throwable $exception): void
{
    $lines = [
        'Upgrade model ' . $model . ' failed.',
        get_class($exception) . ': ' . $exception->getMessage(),
        'File: ' . $exception->getFile() . ':' . $exception->getLine(),
        'Stack trace:',
        $exception->getTraceAsString(),
    ];
    fwrite(STDERR, implode(PHP_EOL, $lines) . PHP_EOL);
}

function config_problem(): string
{
    if (!is_file(CONFIG_FILE)) {
        return CONFIG_FILE . ' is missing';
    }
    load_store_config();
    $missing = [];
    if (db_value('DB_HOSTNAME') === '') {
        $missing[] = 'DB_HOSTNAME';
    }
    if (db_value('DB_USERNAME') === '') {
        $missing[] = 'DB_USERNAME';
    }
    if ($missing === []) {
        return '';
    }
    return CONFIG_FILE . ' is missing ' . implode(' and ', $missing);
}

function retarget_upgrade_admin_paths(array $files, string $adminDir): void
{
    if ($adminDir === 'admin') {
        return;
    }
    if (!preg_match('/^[A-Za-z0-9._-]+$/', $adminDir)) {
        fail('Refusing admin directory name: ' . $adminDir);
    }

    foreach ($files as $file) {
        $source = file_get_contents($file);
        if ($source === false) {
            fail('Could not read ' . $file);
        }
        $updated = str_replace(
            ['admin/config.php', "'/admin/", '"/admin/'],
            [$adminDir . '/config.php', "'/" . $adminDir . '/', '"/' . $adminDir . '/'],
            $source
        );
        if ($updated === $source) {
            continue;
        }
        if (file_put_contents($file, $updated) === false) {
            fail('Could not point ' . basename($file) . ' at the admin directory');
        }
    }
}

function run_upgrade_models(array $settings): void
{
    define_install_paths();

    if (!defined('DB_DRIVER')) {
        define('DB_DRIVER', $settings['driver']);
    }
    if (!defined('DB_HOSTNAME')) {
        define('DB_HOSTNAME', $settings['hostname']);
    }
    if (!defined('DB_USERNAME')) {
        define('DB_USERNAME', $settings['username']);
    }
    if (!defined('DB_PASSWORD')) {
        define('DB_PASSWORD', $settings['password']);
    }
    if (!defined('DB_DATABASE')) {
        define('DB_DATABASE', $settings['database']);
    }
    if (!defined('DB_PORT')) {
        define('DB_PORT', (string) $settings['port']);
    }
    if (!defined('DB_PREFIX')) {
        define('DB_PREFIX', $settings['prefix']);
    }

    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $_SERVER['SERVER_PORT'] = $_SERVER['SERVER_PORT'] ?? '80';
    $_SERVER['DOCUMENT_ROOT'] = HTML_ROOT;

    if (!defined('VERSION')) {
        define('VERSION', OPENCART_VERSION);
    }

    require_once DIR_SYSTEM . 'startup.php';

    $registry = new Registry();
    $loader = new Loader($registry);
    $registry->set('load', $loader);
    $registry->set('db', new DB(DB_DRIVER, DB_HOSTNAME, DB_USERNAME, DB_PASSWORD, DB_DATABASE, DB_PORT));
    // Model 1006 calls cache->delete(). The shop cache is not needed for the schema change.
    $registry->set('cache', new class {
        public function get($key)
        {
            return null;
        }

        public function set($key, $value, $expire = 0): void
        {
        }

        public function delete($key): void
        {
        }
    });

    $files = glob(DIR_APPLICATION . 'model/upgrade/*.php');
    if (!$files) {
        fail('No OpenCart upgrade models were found');
    }
    sort($files, SORT_STRING);

    $adminDir = admin_directory();
    fwrite(STDOUT, 'Using admin directory ' . $adminDir . PHP_EOL);
    if (!is_file(HTML_ROOT . $adminDir . '/config.php')) {
        fail('Admin config was not found for directory ' . $adminDir);
    }
    retarget_upgrade_admin_paths($files, $adminDir);

    $snapshots = snapshot_configs();
    try {
        foreach ($files as $file) {
            $name = basename($file, '.php');
            fwrite(STDOUT, 'Running upgrade ' . $name . PHP_EOL);
            require_once $file;
            $class = 'ModelUpgrade' . preg_replace('/[^a-zA-Z0-9]/', '', $name);
            if (!class_exists($class)) {
                fail('Upgrade class ' . $class . ' was not found');
            }
            $model = new $class($registry);
            try {
                $model->upgrade();
            } catch (Throwable $exception) {
                report_upgrade_failure($name, $exception);
                fail('Upgrade model ' . $name . ' failed.');
            }
        }
    } finally {
        restore_configs($snapshots);
    }
}

function upgrade_if_needed(): void
{
    $settings = connection_settings();
    if ($settings['database'] === '') {
        fail('Database name is missing from config.php');
    }

    try {
        $link = connect($settings, true);
    } catch (Throwable $exception) {
        fail('Database connection failed: ' . $exception->getMessage());
    }
    $lockName = 'oc3051_' . substr(md5($settings['database'] . '|' . $settings['prefix']), 0, 32);
    $escapedLock = $link->real_escape_string($lockName);

    register_shutdown_function(static function () use ($link, $escapedLock): void {
        @$link->query("SELECT RELEASE_LOCK('{$escapedLock}')");
    });

    $lock = $link->query("SELECT GET_LOCK('{$escapedLock}', 900) AS locked");
    $row = $lock instanceof mysqli_result ? $lock->fetch_assoc() : null;
    if (!$row || (string) $row['locked'] !== '1') {
        fail('Timed out waiting for the database upgrade lock');
    }

    $current = marker_value($link, $settings['prefix']);
    if ($current === OPENCART_VERSION) {
        fwrite(STDOUT, 'Database is already OpenCart ' . OPENCART_VERSION . PHP_EOL);
        return;
    }

    // A previous attempt may have paused modifications and then stopped.
    resume_modifications($link, $settings['prefix']);

    $backupDir = storage_path() . 'backup';
    if (!is_dir($backupDir) && !mkdir($backupDir, 0775, true) && !is_dir($backupDir)) {
        warn('Could not create ' . $backupDir . '. The schema upgrade will continue without a database dump.');
    } else {
        $dump = $backupDir . '/pre-upgrade-' . gmdate('Ymd-His') . '.sql';
        fwrite(STDOUT, 'Writing database dump to ' . $dump . PHP_EOL);
        if (dump_database($settings, $dump)) {
            chmod($dump, 0640);
        }
    }

    register_shutdown_function(static function () use ($link, $settings): void {
        resume_modifications($link, $settings['prefix']);
    });

    try {
        pause_enabled_modifications($link, $settings['prefix']);
        try {
            run_upgrade_models($settings);
        } catch (Throwable $exception) {
            fail('Upgrade failed: ' . $exception->getMessage());
        }

        try {
            clear_directory(storage_path() . 'cache');
            clear_directory(storage_path() . 'modification');
        } catch (Throwable $exception) {
            fail('Could not clear cache: ' . $exception->getMessage());
        }
        write_marker($link, $settings['prefix']);
        fwrite(STDOUT, 'Database upgraded to OpenCart ' . OPENCART_VERSION . PHP_EOL);
    } finally {
        resume_modifications($link, $settings['prefix']);
    }
}

function mark_installed(): void
{
    $settings = connection_settings();
    if ($settings['database'] === '') {
        fail('Database name is missing from config.php');
    }

    try {
        $link = connect($settings, true);
    } catch (Throwable $exception) {
        fail('Database connection failed: ' . $exception->getMessage());
    }

    $lockName = 'oc3051_' . substr(md5($settings['database'] . '|' . $settings['prefix']), 0, 32);
    $escapedLock = $link->real_escape_string($lockName);
    register_shutdown_function(static function () use ($link, $escapedLock): void {
        @$link->query("SELECT RELEASE_LOCK('{$escapedLock}')");
    });

    $lock = $link->query("SELECT GET_LOCK('{$escapedLock}', 900) AS locked");
    $row = $lock instanceof mysqli_result ? $lock->fetch_assoc() : null;
    if (!$row || (string) $row['locked'] !== '1') {
        fail('Timed out waiting for the database upgrade lock');
    }

    if (marker_value($link, $settings['prefix']) === OPENCART_VERSION) {
        fwrite(STDOUT, 'Database is already OpenCart ' . OPENCART_VERSION . PHP_EOL);
        return;
    }

    write_marker($link, $settings['prefix']);
    fwrite(STDOUT, 'Recorded OpenCart ' . OPENCART_VERSION . ' without a schema upgrade' . PHP_EOL);
}

function setting_value(mysqli $link, string $prefix, string $key): ?string
{
    $table = '`' . $prefix . 'setting`';
    $escapedKey = $link->real_escape_string($key);
    $result = $link->query("SELECT `value` FROM {$table} WHERE `key` = '{$escapedKey}' AND store_id = 0 ORDER BY setting_id DESC LIMIT 1");
    $row = $result instanceof mysqli_result ? $result->fetch_assoc() : null;
    if (!$row || !array_key_exists('value', $row)) {
        return null;
    }
    return (string) $row['value'];
}

function update_setting(mysqli $link, string $prefix, string $key, string $value): void
{
    $table = '`' . $prefix . 'setting`';
    $escapedKey = $link->real_escape_string($key);
    $escapedValue = $link->real_escape_string($value);
    if (!$link->query("UPDATE {$table} SET `value` = '{$escapedValue}' WHERE `key` = '{$escapedKey}' AND store_id = 0")) {
        fail('Could not set ' . $key);
    }
    if (setting_value($link, $prefix, $key) !== $value) {
        fail('Could not set ' . $key);
    }
}

function apply_store_settings(string $firstname, string $lastname, string $siteName): void
{
    if ($firstname === '' && $lastname === '' && $siteName === '') {
        fwrite(STDOUT, 'No optional store settings supplied' . PHP_EOL);
        return;
    }

    $settings = connection_settings();
    try {
        $link = connect($settings, true);
    } catch (Throwable $exception) {
        fail('Database connection failed: ' . $exception->getMessage());
    }

    $prefix = $settings['prefix'];
    if ($firstname !== '' || $lastname !== '') {
        $assignments = [];
        if ($firstname !== '') {
            $assignments[] = "firstname = '" . $link->real_escape_string($firstname) . "'";
        }
        if ($lastname !== '') {
            $assignments[] = "lastname = '" . $link->real_escape_string($lastname) . "'";
        }
        if (!$link->query('UPDATE `' . $prefix . 'user` SET ' . implode(', ', $assignments) . ' WHERE user_id = 1')) {
            fail('Could not set the admin name');
        }
        $check = $link->query('SELECT firstname, lastname FROM `' . $prefix . 'user` WHERE user_id = 1');
        $user = $check instanceof mysqli_result ? $check->fetch_assoc() : null;
        if (!$user
            || ($firstname !== '' && (string) $user['firstname'] !== $firstname)
            || ($lastname !== '' && (string) $user['lastname'] !== $lastname)
        ) {
            fail('Could not set the admin name');
        }
        update_setting($link, $prefix, 'config_owner', trim((string) $user['firstname'] . ' ' . (string) $user['lastname']));
    }

    if ($siteName !== '') {
        update_setting($link, $prefix, 'config_name', $siteName);
        update_setting($link, $prefix, 'config_meta_title', $siteName);
    }

    $link->close();
    fwrite(STDOUT, 'Optional store settings applied' . PHP_EOL);
}

function marker_is_current(): bool
{
    $settings = connection_settings();
    if ($settings['database'] === '') {
        return false;
    }
    try {
        $link = connect($settings, true);
    } catch (Throwable $exception) {
        return false;
    }
    $current = marker_value($link, $settings['prefix']);
    $link->close();
    return $current === OPENCART_VERSION;
}

function installed_version(): string
{
    $index = HTML_ROOT . 'index.php';
    if (!is_file($index)) {
        return '';
    }
    $contents = file_get_contents($index);
    if ($contents !== false && preg_match("/define\\(\\s*'VERSION'\\s*,\\s*'([^']+)'\\s*\\)/", $contents, $match)) {
        return $match[1];
    }
    return '';
}

$command = $argv[1] ?? '';

switch ($command) {
    case 'configured':
        exit(store_configured() ? 0 : 1);
    case 'config-problem':
        $problem = config_problem();
        if ($problem !== '') {
            fwrite(STDOUT, $problem);
        }
        exit($problem === '' ? 0 : 1);
    case 'export':
        $target = $argv[2] ?? '';
        if ($target === '') {
            fail('export requires a destination path');
        }
        export_env($target);
        exit(0);
    case 'tables':
        exit(tables_exist() ? 0 : 1);
    case 'ping':
        try {
            connect(connection_settings(), false);
        } catch (Throwable $exception) {
            fail($exception->getMessage());
        }
        exit(0);
    case 'storage-path':
        fwrite(STDOUT, storage_path());
        exit(0);
    case 'admin-directory':
        fwrite(STDOUT, admin_directory());
        exit(0);
    case 'version':
        fwrite(STDOUT, installed_version());
        exit(0);
    case 'upgrade-if-needed':
        upgrade_if_needed();
        exit(0);
    case 'mark':
        mark_installed();
        exit(0);
    case 'apply-store':
        apply_store_settings($argv[2] ?? '', $argv[3] ?? '', $argv[4] ?? '');
        exit(0);
    case 'current':
        exit(marker_is_current() ? 0 : 1);
    case 'quiet-extensions':
        quiet_incompatible_extensions();
        resume_modifications();
        exit(0);
    default:
        fail('Usage: opencart-maint.php configured|config-problem|export|tables|ping|storage-path|admin-directory|version|upgrade-if-needed|mark|apply-store|current|quiet-extensions');
}
