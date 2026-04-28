<?php
if(!isset($_SESSION)) session_start();
date_default_timezone_set('Asia/Jakarta');
ini_set('memory_limit', '256M');
$date = date('Y-m-d');
$time = date('H:i:s');
$dtme = date('Y-m-d H:i:s');

// =============================================
// KONFIGURASI DATABASE
// Ganti dengan kredensial cPanel kamu
// =============================================
$aiy = [
    'host' => 'localhost',
    'user' => 'YOUR_DB_USER',   // cPanel: username_dbuser
    'pass' => 'YOUR_DB_PASS',   // password database
    'name' => 'YOUR_DB_NAME'    // cPanel: username_dbname
];

$call = mysqli_connect($aiy['host'], $aiy['user'], $aiy['pass'], $aiy['name']);
if(!$call) {
    // Tampilkan error yang jelas saat DB gagal konek
    $err_msg = mysqli_connect_error();
    error_log("[SSM] DB Connection Failed: " . $err_msg);
    die('<!DOCTYPE html><html><head><title>Service Unavailable</title>
    <style>body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f5f5f5;}
    .box{background:#fff;padding:40px;border-radius:8px;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,.1);}
    h2{color:#e74c3c;}p{color:#666;}</style></head>
    <body><div class="box"><h2>&#9888; Database Error</h2>
    <p>Tidak dapat terhubung ke database.<br>Periksa konfigurasi di <code>connect.php</code></p></div></body></html>');
}

// Set charset untuk mencegah encoding issues
mysqli_set_charset($call, 'utf8mb4');

function _DIR_($path, $x = 'php') {
    // Gunakan DOCUMENT_ROOT langsung — lebih efisien, tidak perlu query DB
    $DROOT = rtrim($_SERVER['DOCUMENT_ROOT'], '/');
    if($x == 'php') return (stristr($path, '.php')) ? "$DROOT/$path" : "$DROOT/$path.php";
    else return "$DROOT/$path";
}

function ShennQuire($f, $x) {
    for($i = 0; $i <= count($x)-1; $i++) require _DIR_($f.$x[$i]);
}

require _DIR_('library/mainfunction');   // This file must be called first!
require _DIR_('library/function/csrf_token');
require _DIR_('library/function/cURL');
require _DIR_('library/function/mailer');
require _DIR_('library/function/SimCardDetector');
require _DIR_('library/customfunction'); // This file must be called last!
require _DIR_('library/database');       // This file must be called last!

$_CONFIG = [
    'title'         => conf('webcfg',1),
    'navbar'        => conf('webcfg',2),
    'description'   => conf('webcfg',3),
    'keyword'       => conf('webcfg',4),
    'banner'        => conf('webcfg',5),
    'icon'          => conf('webcfg',6),
    'hold'          => [
        'Basic'   => conf('hold-balance',1),
        'Premium' => conf('hold-balance',2),
        'Admin'   => conf('hold-balance',3),
    ],
    'lock'          => check_lock(isset($_SESSION['user']['username']) ? $_SESSION['user']['username'] : ''),
    'mt'            => [
        'web' => conf('webmt',1),
        'api' => conf('webmt',2),
        'bot' => [
            'telegram' => conf('webmt',4),
            'whatsapp' => conf('webmt',3)
        ],
        'trx'   => conf('webmt',5),
        'topup' => conf('webmt',6)
    ],
    'reCAPTCHA' => [
        'site'   => conf('webcfg',7),
        'secret' => conf('webcfg',8)
    ],
    'firebase' => (conf('firebase',8) == 'true') ? 'true' : 'false',
    'license'  => conf('license',1),
];

$_META = [
    'robots'          => 'index, follow',
    'revisit'         => '1 days',
    'bing_site'       => 'D00E1C1DD990CCE27CFAB8A295D202C4',
    'google_site'     => 'nuqTjnjDZ-4ufOiWTdhnsLKRkE2PIolE0Op-ZUW07cM',
    'google_tagmanager' => 'GTM-TAGCODE',
    'geo_placename'   => 'Indonesia',
    'geo_country'     => 'Id'
];

$_MAILER = [
    'host' => conf('mailer',1),
    'user' => conf('mailer',2),
    'pass' => conf('mailer',3),
    'from' => conf('mailer',4),
];

$_USER = [
    'theme'   => 'light-layout',
    'require' => [
        'location' => (conf('xtra-fitur',6) == 'true') ? 'true' : 'false',
    ]
];

// ========================= START: Custom Required ========================= //

/* Required: Developer Mode */
if(conf('xtra-fitur',7) == 'true') {
    error_reporting(E_ALL);
    ini_set('display_errors', 1);
} else {
    error_reporting(0);
    ini_set('display_errors', 0);
}

/* Required: Firebase Cloud Messaging */
require _DIR_('library/function/FirebaseCM');
$FCM = new FirebaseCM(conf('firebase',1), conf('firebase',3), conf('firebase',4));

/* Required: Atlantic WhatsApp */
require _DIR_('library/function/AtlanticWhatsapp');
$WATL = new WhatsATL(conf('atlantic-cfg',1), conf('atlantic-cfg',2), conf('atlantic-cfg',4));

/* Required: DigiFlazz */
require _DIR_('library/function/Digiflazz');
$digi_row = $call->query("SELECT * FROM provider WHERE code = 'DIGI'")->fetch_assoc();
$DIGI = new DigiFlazz([
    'username' => $digi_row['userid'] ?? '',
    'apikey'   => $digi_row['apikey'] ?? ''
]);

// ========================== END: Custom Required ========================== //

if(preg_match('#Mozilla/4.05 [fr] (Win98; I)#', $user_agent)
    || preg_match('/Java1.1.4/si', $user_agent)
    || preg_match('/MS FrontPage Express/si', $user_agent)
    || preg_match('/HTTrack/si', $user_agent)
    || preg_match('/IDentity/si', $user_agent)
    || preg_match('/HyperBrowser/si', $user_agent)
    || preg_match('/Lynx/si', $user_agent)
) die('#');

$page_load       = explode(' ', microtime());
$page_load       = $page_load[1] + $page_load[0];
$page_load_start = $page_load;
