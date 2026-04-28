#!/bin/bash
# ============================================================
#   SSM Panel - Auto Installer
#   Author : sheriflks | github.com/sheriflks/ssm
#   Tested : Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ask()  { echo -ne "${YELLOW}[?]${NC} $1"; }
step() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ── Root ─────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && die "Jalankan sebagai root: sudo bash install.sh"

echo -e "${CYAN}${BOLD}"
echo "  ____  ____  __  __ "
echo " / ___||  _ \|  \/  |"
echo " \___ \| |_) | |\/| |"
echo "  ___) |  __/| |  | |"
echo " |____/|_|   |_|  |_|"
echo -e "${NC}${GREEN}${BOLD}  SSM Panel Installer — Fresh VPS Ready${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ════════════════════════════════════════════
# 0. DETEKSI OS
# ════════════════════════════════════════════
[ -f /etc/os-release ] || die "Tidak bisa baca /etc/os-release"
. /etc/os-release
OS_NAME="${ID:-unknown}"
info "OS: ${PRETTY_NAME:-unknown}"
case "$OS_NAME" in
  ubuntu|debian) : ;;
  *) die "OS tidak didukung. Gunakan Ubuntu 20/22/24 atau Debian 11/12." ;;
esac

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# ════════════════════════════════════════════
# 1. INPUT
# ════════════════════════════════════════════
step "INPUT"
ask "Domain (contoh: ssm.sherif.eu.cc): "; read -r DOMAIN
[ -z "${DOMAIN:-}" ] && die "Domain tidak boleh kosong."

ask "Webroot (default: /var/www/html/ssm): "; read -r WEBROOT
WEBROOT="${WEBROOT:-/var/www/html/ssm}"

ask "Nama database (default: ssm_db): "; read -r DB_NAME
DB_NAME="${DB_NAME:-ssm_db}"

ask "Username DB (default: ssm_user): "; read -r DB_USER
DB_USER="${DB_USER:-ssm_user}"

ask "Password DB baru: "; read -rs DB_PASS; echo ""
[ -z "${DB_PASS:-}" ] && die "Password DB tidak boleh kosong."

echo -e "\n${YELLOW}Password root MySQL — kosongkan jika fresh install:${NC}"
ask "Password root MySQL: "; read -rs MYSQL_ROOT_PASS; echo ""

echo ""
echo -e "${BOLD}  Domain  : $DOMAIN"
echo -e "  Webroot : $WEBROOT"
echo -e "  DB Name : $DB_NAME"
echo -e "  DB User : $DB_USER${NC}"
echo ""
ask "Lanjutkan? (y/n): "; read -r CONFIRM
[[ "${CONFIRM:-n}" != "y" && "${CONFIRM:-n}" != "Y" ]] && echo "Dibatalkan." && exit 0

# ════════════════════════════════════════════
# 2. BOOTSTRAP — tool dasar
# ════════════════════════════════════════════
step "BOOTSTRAP"
dpkg --configure -a 2>/dev/null || true
apt-get update -y 2>&1 | tail -2
apt-get install -y --no-install-recommends \
  curl wget git unzip rsync \
  gnupg ca-certificates lsb-release \
  apt-transport-https software-properties-common \
  net-tools psmisc iproute2 cron 2>&1 | tail -3
ok "Tool dasar siap."

# ════════════════════════════════════════════
# 3. CLEANUP — hapus semua yang bentrok
# ════════════════════════════════════════════
step "CLEANUP"

# Stop & disable service yang bentrok di port 80/443
for svc in nginx lighttpd caddy h2o; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    warn "Menghentikan $svc yang bentrok..."
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  fi
done

# Kill paksa proses di port 80 dan 443
fuser -k 80/tcp  2>/dev/null || true
fuser -k 443/tcp 2>/dev/null || true
sleep 1

# Hapus webroot lama jika ada
if [ -d "$WEBROOT" ] && [ -n "$(ls -A "$WEBROOT" 2>/dev/null)" ]; then
  warn "Webroot lama ditemukan: $WEBROOT"
  ask "Hapus webroot + database lama? (y/n): "; read -r CLEAN_CONFIRM
  if [[ "${CLEAN_CONFIRM:-n}" == "y" || "${CLEAN_CONFIRM:-n}" == "Y" ]]; then
    rm -rf "$WEBROOT"
    ok "Webroot lama dihapus."
    DROP_OLD_DB=1
  else
    warn "Skip cleanup, file lama akan ditimpa."
    DROP_OLD_DB=0
  fi
else
  DROP_OLD_DB=0
fi

# Hapus Apache site lama yang mungkin konflik
rm -f /etc/apache2/sites-enabled/*.conf  2>/dev/null || true
rm -f /etc/apache2/sites-available/ssm.conf 2>/dev/null || true

ok "Cleanup selesai."

# ════════════════════════════════════════════
# 4. INSTALL PAKET
# ════════════════════════════════════════════
step "INSTALL PAKET"

# Tambah repo PHP
if [ "$OS_NAME" = "ubuntu" ]; then
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php 2>&1 | tail -2 || true
elif [ "$OS_NAME" = "debian" ]; then
  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg 2>/dev/null || true
  echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/sury-php.list
fi
apt-get update -y 2>&1 | tail -2

# Pilih versi PHP terbaik
PHP_VER=""
for v in 8.2 8.1 8.0 7.4; do
  apt-cache show "php${v}" &>/dev/null 2>&1 && PHP_VER="$v" && break
done
[ -z "$PHP_VER" ] && PHP_VER="8.1"
info "PHP versi: $PHP_VER"

apt-get install -y \
  apache2 \
  mysql-server \
  "php${PHP_VER}" \
  "php${PHP_VER}-cli" \
  "php${PHP_VER}-mysql" \
  "php${PHP_VER}-curl" \
  "php${PHP_VER}-mbstring" \
  "php${PHP_VER}-xml" \
  "php${PHP_VER}-zip" \
  "php${PHP_VER}-gd" \
  "php${PHP_VER}-bcmath" \
  "php${PHP_VER}-intl" \
  "php${PHP_VER}-opcache" \
  "php${PHP_VER}-readline" \
  "libapache2-mod-php${PHP_VER}" \
  certbot python3-certbot-apache 2>&1 | tail -5

# Set PHP default
update-alternatives --set php "/usr/bin/php${PHP_VER}" 2>/dev/null || true

# Verifikasi
PHP_VER_INSTALLED=$(php -r "echo PHP_VERSION;" 2>/dev/null || echo "")
[ -z "$PHP_VER_INSTALLED" ] && die "PHP gagal diinstall."
ok "PHP $PHP_VER_INSTALLED terinstall."

# Cek extension wajib
MISS=""
for ext in curl mbstring xml zip gd bcmath mysqli json opcache; do
  php -m 2>/dev/null | grep -qi "^${ext}$" || MISS="$MISS $ext"
done
if [ -n "$MISS" ]; then
  warn "Extension missing:$MISS — install ulang..."
  for ext in $MISS; do
    apt-get install -y "php${PHP_VER}-${ext}" 2>/dev/null || \
    apt-get install -y "php-${ext}" 2>/dev/null || true
  done
fi
ok "PHP extensions OK."

# ════════════════════════════════════════════
# 5. KONFIGURASI APACHE
# ════════════════════════════════════════════
step "KONFIGURASI APACHE"

# Aktifkan modul
a2enmod rewrite headers ssl deflate expires php${PHP_VER} 2>&1 | grep -v "already enabled" || true

# Buat vhost
mkdir -p "$WEBROOT"
cat > /etc/apache2/sites-available/ssm.conf << VHOST
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${WEBROOT}

    <Directory ${WEBROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript application/json
    </IfModule>

    ErrorLog \${APACHE_LOG_DIR}/ssm_error.log
    CustomLog \${APACHE_LOG_DIR}/ssm_access.log combined
</VirtualHost>
VHOST

a2ensite ssm.conf
a2dissite 000-default.conf 2>/dev/null || true

# Pastikan port 80 bebas lagi sebelum start
fuser -k 80/tcp 2>/dev/null || true
sleep 1

systemctl enable apache2
systemctl restart apache2
sleep 2

if systemctl is-active --quiet apache2; then
  ok "Apache running."
else
  # Coba diagnosa
  journalctl -xeu apache2.service --no-pager -n 20 2>/dev/null || true
  die "Apache gagal start. Lihat log di atas."
fi

# ════════════════════════════════════════════
# 6. DEPLOY FILE PROJECT
# ════════════════════════════════════════════
step "DEPLOY FILE PROJECT"

# Deteksi lokasi script
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

info "Source : $SCRIPT_DIR"
info "Target : $WEBROOT"

if [ "$SCRIPT_DIR" = "$WEBROOT" ]; then
  info "Script sudah di webroot, skip copy."
elif [ -f "$SCRIPT_DIR/connect.php" ]; then
  rsync -a --exclude='.git' "$SCRIPT_DIR/" "$WEBROOT/" 2>/dev/null || \
    cp -r "$SCRIPT_DIR/." "$WEBROOT/"
  ok "File project disalin."
else
  warn "File tidak ada di $SCRIPT_DIR, clone dari GitHub..."
  rm -rf "$WEBROOT"
  git clone https://github.com/sheriflks/ssm.git "$WEBROOT" 2>&1 | tail -3
  ok "Project di-clone dari GitHub."
fi

# Permission
chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"
[ -d "$WEBROOT/library/assets" ] && chmod -R 775 "$WEBROOT/library/assets"
[ -f "$WEBROOT/library/shenn.log" ] && chmod 664 "$WEBROOT/library/shenn.log" || true
ok "Permission diset."

# ════════════════════════════════════════════
# 7. SETUP MYSQL
# ════════════════════════════════════════════
step "SETUP MYSQL"

systemctl enable mysql
systemctl start mysql

# Tunggu MySQL ready
info "Menunggu MySQL siap..."
for i in $(seq 1 20); do
  mysqladmin ping --silent 2>/dev/null && break
  sleep 1
done

# Tentukan cara koneksi — coba semua metode
MYSQL_CMD=""
if mysql -u root --batch --silent -e "SELECT 1;" 2>/dev/null; then
  MYSQL_CMD="mysql -u root"
  info "MySQL: auth_socket"
elif [ -n "${MYSQL_ROOT_PASS:-}" ] && \
     mysql -u root -p"${MYSQL_ROOT_PASS}" --batch --silent -e "SELECT 1;" 2>/dev/null; then
  MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASS}"
  info "MySQL: password"
elif sudo mysql -u root --batch --silent -e "SELECT 1;" 2>/dev/null; then
  MYSQL_CMD="sudo mysql -u root"
  info "MySQL: sudo auth_socket"
else
  # Last resort: reset MySQL root via unix socket
  warn "Semua metode koneksi gagal, mencoba reset MySQL root..."
  systemctl stop mysql 2>/dev/null || true
  mysqld_safe --skip-grant-tables --skip-networking &
  sleep 5
  mysql -u root --batch --silent << 'SQLINIT' 2>/dev/null || true
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
SQLINIT
  kill %1 2>/dev/null || true
  sleep 2
  systemctl start mysql
  sleep 3
  if mysql -u root --batch --silent -e "SELECT 1;" 2>/dev/null; then
    MYSQL_CMD="mysql -u root"
  else
    die "Tidak bisa konek MySQL. Jalankan manual: sudo mysql_secure_installation"
  fi
fi

# Drop DB lama jika diminta
if [ "${DROP_OLD_DB:-0}" -eq 1 ]; then
  info "Drop database lama '${DB_NAME}'..."
  $MYSQL_CMD --batch --silent 2>/dev/null << EOF || true
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
  ok "Database lama dihapus."
fi

# Buat DB dan user baru
$MYSQL_CMD --batch --silent << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
[ $? -ne 0 ] && die "Gagal buat database/user MySQL."
ok "Database '${DB_NAME}' dan user '${DB_USER}' siap."

# ════════════════════════════════════════════
# 8. IMPORT DATABASE.SQL
# ════════════════════════════════════════════
step "IMPORT DATABASE.SQL"

SQL_FILE="$WEBROOT/Database.sql"
[ ! -f "$SQL_FILE" ] && die "Database.sql tidak ditemukan di $WEBROOT"

info "Import Database.sql ke '${DB_NAME}'..."
$MYSQL_CMD --batch "${DB_NAME}" < "$SQL_FILE"
[ $? -ne 0 ] && die "Gagal import Database.sql."
ok "Database.sql berhasil diimport."

# ════════════════════════════════════════════
# 9. UPDATE CONNECT.PHP
# ════════════════════════════════════════════
step "UPDATE CONNECT.PHP"

CONNECT="$WEBROOT/connect.php"
[ ! -f "$CONNECT" ] && die "connect.php tidak ditemukan."

# Tulis ulang blok $aiy secara langsung — paling aman, tidak bergantung regex
# Cari baris 'host', 'user', 'pass', 'name' di dalam array $aiy dan ganti nilainya
# Gunakan Python3 yang pasti ada di semua Ubuntu/Debian modern
python3 << PYEOF
import re, sys

filepath = '${CONNECT}'
db_host  = 'localhost'
db_user  = '${DB_USER}'
db_pass  = '${DB_PASS}'
db_name  = '${DB_NAME}'

try:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
except Exception as e:
    print(f"GAGAL baca: {e}", file=sys.stderr)
    sys.exit(1)

# Ganti nilai dalam array \$aiy — handle komentar setelah value (# ...)
def replace_key(content, key, value):
    # Pattern: 'key' => 'nilai_lama' dengan optional komentar setelahnya
    pattern = r"('" + key + r"'\s*=>\s*')[^']*(')"
    replacement = r'\g<1>' + value + r'\g<2>'
    new_content, n = re.subn(pattern, replacement, content)
    if n == 0:
        print(f"WARN: key '{key}' tidak ditemukan", file=sys.stderr)
    return new_content

content = replace_key(content, 'host', db_host)
content = replace_key(content, 'user', db_user)
content = replace_key(content, 'pass', db_pass)
content = replace_key(content, 'name', db_name)

try:
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("OK")
except Exception as e:
    print(f"GAGAL tulis: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

if [ $? -ne 0 ]; then
  die "Gagal update connect.php."
fi

# Verifikasi isi connect.php tidak rusak
php -l "$CONNECT" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  die "connect.php syntax error setelah diedit! Cek: php -l $CONNECT"
fi
ok "connect.php syntax OK."

# Verifikasi nilai DB sudah masuk
if grep -q "'name' => '${DB_NAME}'" "$CONNECT"; then
  ok "connect.php dikonfigurasi dengan benar."
else
  warn "Verifikasi gagal, tampilkan isi \$aiy:"
  grep -A5 '\$aiy = \[' "$CONNECT" || true
fi

# Test koneksi PHP → MySQL
info "Test koneksi PHP → MySQL..."
TEST_RESULT=$(php -r "
\$c = @mysqli_connect('localhost','${DB_USER}','${DB_PASS}','${DB_NAME}');
if(\$c) { echo 'OK'; mysqli_close(\$c); } else { echo 'FAIL:'.mysqli_connect_error(); }
" 2>/dev/null)

if [ "$TEST_RESULT" = "OK" ]; then
  ok "Koneksi PHP → MySQL: BERHASIL"
else
  die "Koneksi PHP → MySQL GAGAL: $TEST_RESULT — cek DB_USER/DB_PASS/DB_NAME."
fi

# ════════════════════════════════════════════
# 10. PHP CONFIG — fix error display
# ════════════════════════════════════════════
step "PHP CONFIG"

PHP_INI=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk '{print $NF}')
if [ -f "$PHP_INI" ]; then
  sed -i 's/^display_errors\s*=.*/display_errors = Off/' "$PHP_INI"
  sed -i 's/^error_reporting\s*=.*/error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_STRICT/' "$PHP_INI"
  ok "PHP error display dimatikan (production mode)."
fi

# Apache PHP config
APACHE_PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"
if [ -f "$APACHE_PHP_INI" ]; then
  sed -i 's/^display_errors\s*=.*/display_errors = Off/' "$APACHE_PHP_INI"
  sed -i 's/^memory_limit\s*=.*/memory_limit = 256M/' "$APACHE_PHP_INI"
  sed -i 's/^upload_max_filesize\s*=.*/upload_max_filesize = 64M/' "$APACHE_PHP_INI"
  sed -i 's/^post_max_size\s*=.*/post_max_size = 64M/' "$APACHE_PHP_INI"
  sed -i 's/^max_execution_time\s*=.*/max_execution_time = 300/' "$APACHE_PHP_INI"
  ok "PHP Apache config dioptimasi."
fi

systemctl restart apache2

# ════════════════════════════════════════════
# 11. SSL
# ════════════════════════════════════════════
step "SSL (Let's Encrypt)"

ask "Setup SSL untuk ${DOMAIN}? (y/n): "; read -r SSL_CONFIRM
if [[ "${SSL_CONFIRM:-n}" == "y" || "${SSL_CONFIRM:-n}" == "Y" ]]; then

  # Pastikan Apache running
  systemctl is-active --quiet apache2 || systemctl restart apache2

  # Cek DNS
  SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
              curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
  DOMAIN_IP=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || echo "")

  if [ -n "$DOMAIN_IP" ] && [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    warn "DNS $DOMAIN → $DOMAIN_IP, IP VPS ini → $SERVER_IP"
    warn "DNS belum propagate. SSL dilewati."
    warn "Jalankan manual nanti: certbot --apache -d $DOMAIN"
  else
    # Stop Apache sementara agar certbot bisa pakai port 80 standalone jika perlu
    certbot --apache -d "$DOMAIN" \
      --non-interactive --agree-tos \
      -m "admin@${DOMAIN}" \
      --redirect 2>&1

    if [ $? -eq 0 ]; then
      ok "SSL aktif untuk ${DOMAIN}."
      # Update vhost HTTPS agar DocumentRoot benar
      systemctl reload apache2
    else
      warn "SSL gagal. Coba manual: certbot --apache -d ${DOMAIN}"
    fi
  fi
else
  warn "SSL dilewati. Aktifkan manual: certbot --apache -d ${DOMAIN}"
fi

# ════════════════════════════════════════════
# 12. CRON JOB
# ════════════════════════════════════════════
step "CRON JOB"

systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
systemctl start  cron 2>/dev/null || systemctl start  crond 2>/dev/null || true

PHP_BIN=$(which php)
CRON_STATUS="* * * * * ${PHP_BIN} ${WEBROOT}/library/cron/status-socmed.php > /dev/null 2>&1"
CRON_REFUND="* * * * * ${PHP_BIN} ${WEBROOT}/library/cron/refund-socmed.php > /dev/null 2>&1"

CURRENT_CRON=$(crontab -l 2>/dev/null || echo "")
NEW_CRON="$CURRENT_CRON"
echo "$CURRENT_CRON" | grep -qF "status-socmed" || NEW_CRON="${NEW_CRON}"$'\n'"${CRON_STATUS}"
echo "$CURRENT_CRON" | grep -qF "refund-socmed"  || NEW_CRON="${NEW_CRON}"$'\n'"${CRON_REFUND}"
echo "$NEW_CRON" | crontab -
ok "Cron job aktif."

# ════════════════════════════════════════════
# SELESAI
# ════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✓  INSTALASI SELESAI!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  URL     : ${CYAN}https://${DOMAIN}${NC}"
echo -e "  Webroot : ${CYAN}${WEBROOT}${NC}"
echo -e "  DB Name : ${CYAN}${DB_NAME}${NC}"
echo -e "  DB User : ${CYAN}${DB_USER}${NC}"
echo -e "  PHP     : ${CYAN}$(php -r 'echo PHP_VERSION;' 2>/dev/null)${NC}"
echo ""
echo -e "${YELLOW}  Langkah selanjutnya:${NC}"
echo "  1. Buka https://${DOMAIN}"
echo "  2. Konfigurasi di panel admin:"
echo "     SMTP · Payment Gateway · Provider API · Firebase"
echo ""
echo -e "${CYAN}  Cek error log:${NC}"
echo "  tail -f /var/log/apache2/ssm_error.log"
echo ""
