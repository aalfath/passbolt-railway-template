<?php
// Prints the first administrator's pending setup link, if one is still valid.
// Used by railway-start.sh on every boot until the admin finishes setup.
$email = getenv('PASSBOLT_ADMIN_EMAIL');
$base = rtrim((string)getenv('APP_FULL_BASE_URL'), '/');
if (!$email || !$base) { exit(0); }
try {
    $dsn = sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
        getenv('DATASOURCES_DEFAULT_HOST'), getenv('DATASOURCES_DEFAULT_PORT') ?: '3306',
        getenv('DATASOURCES_DEFAULT_DATABASE'));
    $db = new PDO($dsn, getenv('DATASOURCES_DEFAULT_USERNAME'), getenv('DATASOURCES_DEFAULT_PASSWORD'));
    $q = $db->prepare("SELECT u.id, t.token FROM users u JOIN authentication_tokens t ON t.user_id = u.id
        WHERE u.username = ? AND u.active = 0 AND u.deleted = 0 AND t.type = 'register' AND t.active = 1
          AND t.created > (NOW() - INTERVAL 10 DAY) ORDER BY t.created DESC LIMIT 1");
    $q->execute([$email]);
    if ($r = $q->fetch(PDO::FETCH_NUM)) {
        echo "$base/setup/start/{$r[0]}/{$r[1]}\n";
    }
} catch (Throwable $e) {
    fwrite(STDERR, "setup link lookup failed: " . $e->getMessage() . "\n");
}
