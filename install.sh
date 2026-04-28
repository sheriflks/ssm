#!/bin/bash

# ============================================================
#   SSM - Installer Script for VPS
#   Author: sheriflks | github.com/sheriflks/ssm
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ask()  { echo -ne "${YELLOW}[?]${NC} $1"; }

echo -e "${CYAN}${BOLD}"
echo "  ____  ____  __  __ "
echo " / ___||  _ \|  \/  |"
echo " \___ \| |_) | |\/| |"
echo "  ___) |  __/| |  | |"
echo " |____/|_|   |_|  |_|"
echo -e "${NC}"
echo -e "${GREEN}${BOLD}  SSM Panel - Auto Installer${NC}"
echo "============================================"
echo ""

# ── Root check ───────────────────────────────────────────────
[ "$EUID" -ne 0 ] && err "Jalankan sebagai root: sudo bash install.sh"

# ── Deteksi OS ───────────────────────────────────────────────
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="$ID"
  OS_VER="$VERSION_ID"
else
  err "OS tidak dikenali. Script ini mendukung Ubuntu/Debian."
fi

info "OS terdeteksi: $PRETTY_NAME"

case "$OS_NAME" in
  ubuntu|debian) PKG_MGR="apt-get" ;;
  *) err "OS '$OS_NAME' tidak didukung. Gunakan Ubuntu 20.04/22.04 atau Debian 11/12." ;;
esac

# ── Input ────────────────────────────────────────────────────
echo ""
ask "Domain (contoh: ssm.sherif.eu.cc): "; read DOMAIN
[ -z "$DOMAIN" ] && err "Domain tidak boleh kosong."

ask "Direktori install (default: /var/www/html/ssm): "; read WEBROOT
WEBROOT=${WEBROOT:-/var/www/html/ssm}

ask "Nama database (default: ssm_db): "; read DB_NAME
DB_NAME=${DB_NAME:-ssm_db}

ask "Username database (default: ssm_user): "; read DB_USER
DB_USER=${DB_USER:-ssm_user}

ask "Password database baru: "; read -s DB_PASS; echo ""
[ -z "$DB_PASS" ] && err "Password database tidak boleh kosong."

ask "Password root MySQL (kosongkan jika pakai auth_socket/fresh install): "; read -s MYSQL_ROOT_PASS; echo ""

# Tentukan cara koneksi MySQL
if [ -z "$MYSQL_ROOT_PASS" ]; then
  MYSQL_CMD="mysql -u root"
else
  MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASS}"
fi

echo ""
echo -e "${CYAN}${BOLD}[INFO] Konfigurasi:${NC}"
echo "  Domain  : $DOMAIN"
echo "  Webroot : $WEBROOT"
echo "  DB Name : $DB_NAME"
echo "  DB User : $DB_USER"
echo ""
ask "Lanjutkan instalasi? (y/n): "; read CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo -e "${RED}Dibatalkan.${NC}" && exit 0

echo ""
echo -e "${BOLD}============================================${NC}"

# ════════════════════════════════════════════
# STEP 1 — Update sistem & install dependensi
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[1/7] Update sistem & install dependensi...${NC}"

$PKG_MGR update -y
DEBIAN_FRONTEND=noninteractive $PKG_MGR upgrade -y

# Install software-properties-common untuk add-apt-repository
DEBIAN_FRONTEND=noninteractive $PKG_MGR install -y software-properties-common apt-transport-https ca-certificates lsb-release gnupg

# Tambah repo PHP (Ondrej) untuk PHP 8.1
PHP_VER="8.1"
if ! php -v 2>/dev/null | grep -q "PHP 8"; then
  info "Menambahkan repository PHP $PHP_VER (Ondrej)..."
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
  $PKG_MGR update -y
fi

# Install semua paket yang dibutuhkan
info "Menginstall Apache2, MySQL, PHP $PHP_VER + extensions..."
DEBIAN_FRONTEND=noninteractive $PKG_MGR install -y \
  apache2 \
  mysql-server \
  php${PHP_VER} \
  php${PHP_VER}-mysql \
  php${PHP_VER}-curl \
  php${PHP_VER}-mbstring \
  php${PHP_VER}-xml \
  php${PHP_VER}-zip \
  php${PHP_VER}-gd \
  php${PHP_VER}-bcmath \
  php${PHP_VER}-intl \
  php${PHP_VER}-json \
  php${PHP_VER}-opcache \
  php${PHP_VER}-readline \
  libapache2-mod-php${PHP_VER} \
  unzip \
  curl \
  wget \
  git \
  rsync \
  certbot \
  python3-certbot-apache \
  cron

# Set PHP default ke versi yang diinstall
update-alternatives --set php /usr/bin/php${PHP_VER} 2>/dev/null || true

ok "Semua dependensi terinstall."

# Verifikasi PHP
PHP_INSTALLED=$(php -r "echo PHP_VERSION;" 2>/dev/null || echo "")
[ -z "$PHP_INSTALLED" ] && err "PHP gagal diinstall."
ok "PHP versi: $PHP_INSTALLED"

# Verifikasi ekstensi PHP yang wajib
info "Verifikasi PHP extensions..."
REQUIRED_EXTS="curl mbstring xml zip gd bcmath pdo_mysql mysqli json opcache"
MISSING_EXTS=""
for ext in $REQUIRED_EXTS; do
  if ! php -m 2>/dev/null | grep -qi "^${ext}$"; then
    MISSING_EXTS="$MISSING_EXTS $ext"
  fi
done

if [ -n "$MISSING_EXTS" ]; then
  warn "Extension berikut tidak terdeteksi, mencoba install ulang:$MISSING_EXTS"
  for ext in $MISSING_EXTS; do
    DEBIAN_FRONTEND=noninteractive $PKG_MGR install -y "php${PHP_VER}-${ext}" 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive $PKG_MGR install -y "php-${ext}" 2>/dev/null || \
    warn "Gagal install php-${ext}, skip."
  done
else
  ok "Semua PHP extensions tersedia."
fi

# ════════════════════════════════════════════
# STEP 2 — Konfigurasi Apache
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[2/7] Konfigurasi Apache...${NC}"

a2enmod rewrite headers ssl deflate expires
systemctl enable apache2
systemctl start apache2

VHOST_FILE="/etc/apache2/sites-available/ssm.conf"
cat > "$VHOST_FILE" << VHOST
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

    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType image/jpg "access plus 1 month"
        ExpiresByType image/jpeg "access plus 1 month"
        ExpiresByType image/png "access plus 1 month"
        ExpiresByType text/css "access plus 1 week"
        ExpiresByType application/javascript "access plus 1 week"
    </IfModule>

    ErrorLog \${APACHE_LOG_DIR}/ssm_error.log
    CustomLog \${APACHE_LOG_DIR}/ssm_access.log combined
</VirtualHost>
VHOST

a2ensite ssm.conf
a2dissite 000-default.conf 2>/dev/null || true
apache2ctl configtest && systemctl restart apache2
ok "Apache dikonfigurasi untuk domain ${DOMAIN}."

# ════════════════════════════════════════════
# STEP 3 — Deploy file project
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[3/7] Deploy file project ke ${WEBROOT}...${NC}"

mkdir -p "$WEBROOT"

# Deteksi lokasi script
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

info "Source: $SCRIPT_DIR"
info "Target: $WEBROOT"

if [ "$SCRIPT_DIR" != "$WEBROOT" ]; then
  if command -v rsync &>/dev/null; then
    rsync -a --exclude='.git' --exclude='install.sh' "$SCRIPT_DIR/" "$WEBROOT/"
  else
    cp -r "$SCRIPT_DIR/." "$WEBROOT/"
  fi
fi

# Set permission
chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"
[ -d "$WEBROOT/library/assets" ]   && chmod -R 775 "$WEBROOT/library/assets"
[ -d "$WEBROOT/library/shenn.log" ] && chmod 664 "$WEBROOT/library/shenn.log" 2>/dev/null || true

ok "File project di-deploy."

# ════════════════════════════════════════════
# STEP 4 — Setup MySQL
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[4/7] Setup database MySQL...${NC}"

systemctl enable mysql
systemctl start mysql

# Coba koneksi MySQL
if ! $MYSQL_CMD --batch --silent -e "SELECT 1;" &>/dev/null; then
  # Fallback: coba dengan sudo/auth_socket
  if sudo mysql -u root --batch --silent -e "SELECT 1;" &>/dev/null; then
    MYSQL_CMD="sudo mysql -u root"
    warn "Menggunakan auth_socket untuk koneksi MySQL."
  else
    err "Tidak bisa konek ke MySQL. Cek password root atau status service MySQL."
  fi
fi

$MYSQL_CMD --batch --silent << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

ok "Database '${DB_NAME}' dan user '${DB_USER}' siap."

# ════════════════════════════════════════════
# STEP 5 — Import Database.sql
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[5/7] Import Database.sql...${NC}"

SQL_FILE="$WEBROOT/Database.sql"
[ ! -f "$SQL_FILE" ] && err "File Database.sql tidak ditemukan di ${WEBROOT}"

info "Mengimport ${SQL_FILE}..."
$MYSQL_CMD --batch "${DB_NAME}" < "$SQL_FILE"
ok "Database.sql berhasil diimport ke '${DB_NAME}'."

# ════════════════════════════════════════════
# STEP 6 — Update connect.php
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[6/7] Update connect.php...${NC}"

CONNECT="$WEBROOT/connect.php"
[ ! -f "$CONNECT" ] && err "connect.php tidak ditemukan di ${WEBROOT}"

# Escape karakter spesial untuk sed
escape_sed() { printf '%s\n' "$1" | sed -e 's/[\/&]/\\&/g'; }

DB_USER_ESC=$(escape_sed "$DB_USER")
DB_PASS_ESC=$(escape_sed "$DB_PASS")
DB_NAME_ESC=$(escape_sed "$DB_NAME")

sed -i "s/'host'\s*=>\s*'[^']*'/'host' => 'localhost'/" "$CONNECT"
sed -i "s/'user'\s*=>\s*'[^']*'/'user' => '${DB_USER_ESC}'/" "$CONNECT"
sed -i "s/'pass'\s*=>\s*'[^']*'/'pass' => '${DB_PASS_ESC}'/" "$CONNECT"
sed -i "s/'name'\s*=>\s*'[^']*'/'name' => '${DB_NAME_ESC}'/" "$CONNECT"

ok "connect.php dikonfigurasi."

# ════════════════════════════════════════════
# STEP 7 — SSL via Certbot
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[7/7] Setup SSL (Let's Encrypt)...${NC}"

ask "Setup SSL otomatis untuk ${DOMAIN}? (y/n): "; read SSL_CONFIRM
if [[ "$SSL_CONFIRM" == "y" || "$SSL_CONFIRM" == "Y" ]]; then
  certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}" --redirect
  if [ $? -eq 0 ]; then
    ok "SSL aktif untuk ${DOMAIN}."
  else
    warn "SSL gagal. Pastikan DNS domain sudah mengarah ke IP VPS ini, lalu jalankan:"
    warn "  certbot --apache -d ${DOMAIN}"
  fi
else
  warn "SSL dilewati. Aktifkan manual: certbot --apache -d ${DOMAIN}"
fi

# ════════════════════════════════════════════
# BONUS — Setup Cron Job
# ════════════════════════════════════════════
echo -e "\n${CYAN}${BOLD}[+] Setup cron job...${NC}"

systemctl enable cron
systemctl start cron

CRON_STATUS="* * * * * php ${WEBROOT}/library/cron/status-socmed.php > /dev/null 2>&1"
CRON_REFUND="* * * * * php ${WEBROOT}/library/cron/refund-socmed.php > /dev/null 2>&1"

(crontab -l 2>/dev/null | grep -qF "status-socmed") || \
  { crontab -l 2>/dev/null; echo "$CRON_STATUS"; } | crontab -
(crontab -l 2>/dev/null | grep -qF "refund-socmed") || \
  { crontab -l 2>/dev/null; echo "$CRON_REFUND"; } | crontab -

ok "Cron job aktif."

# ════════════════════════════════════════════
# SELESAI
# ════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}  INSTALASI SELESAI!${NC}"
echo -e "${GREEN}${BOLD}============================================${NC}"
echo ""
echo -e "  URL     : ${CYAN}https://${DOMAIN}${NC}"
echo -e "  Webroot : ${CYAN}${WEBROOT}${NC}"
echo -e "  DB Name : ${CYAN}${DB_NAME}${NC}"
echo -e "  DB User : ${CYAN}${DB_USER}${NC}"
echo -e "  PHP     : ${CYAN}$(php -r 'echo PHP_VERSION;' 2>/dev/null)${NC}"
echo ""
echo -e "${YELLOW}${BOLD}  Langkah selanjutnya:${NC}"
echo "  1. Buka https://${DOMAIN} di browser"
echo "  2. Login panel admin & konfigurasi:"
echo "     - SMTP (email)"
echo "     - Payment gateway (Paydisini, dll)"
echo "     - Provider (Digiflazz, dll)"
echo "     - Firebase Cloud Messaging"
echo "  3. Cron job sudah aktif otomatis"
echo ""
echo -e "${CYAN}  Cek log Apache jika ada error:${NC}"
echo "  tail -f /var/log/apache2/ssm_error.log"
echo ""
