#!/bin/bash

# ============================================================
#   SSM - Installer Script for VPS (Fresh Install Ready)
#   Author: sheriflks | github.com/sheriflks/ssm
# ============================================================

# Jangan pakai set -euo pipefail di level global karena
# beberapa command boleh gagal (fallback logic)
set -uo pipefail

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

step() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

echo -e "${CYAN}${BOLD}"
echo "  ____  ____  __  __ "
echo " / ___||  _ \|  \/  |"
echo " \___ \| |_) | |\/| |"
echo "  ___) |  __/| |  | |"
echo " |____/|_|   |_|  |_|"
echo -e "${NC}"
echo -e "${GREEN}${BOLD}  SSM Panel - Auto Installer (Fresh VPS Ready)${NC}"
echo "================================================"
echo ""

# ── Root check ───────────────────────────────────────────────
[ "$EUID" -ne 0 ] && err "Jalankan sebagai root: sudo bash install.sh"

# ════════════════════════════════════════════
# BOOTSTRAP — Install tool dasar dulu
# (fresh VPS mungkin belum punya curl, wget, dll)
# ════════════════════════════════════════════
step "BOOTSTRAP — Persiapan sistem dasar"

# Deteksi package manager
if command -v apt-get &>/dev/null; then
  PKG_MGR="apt-get"
elif command -v apt &>/dev/null; then
  PKG_MGR="apt"
else
  err "Package manager apt tidak ditemukan. Script ini hanya mendukung Ubuntu/Debian."
fi

# Deteksi OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="${ID:-unknown}"
  OS_VER="${VERSION_ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-unknown}"
else
  err "Tidak bisa membaca /etc/os-release. Pastikan OS adalah Ubuntu/Debian."
fi

info "OS: $OS_PRETTY"

case "$OS_NAME" in
  ubuntu|debian) : ;;
  *) err "OS '$OS_NAME' tidak didukung. Gunakan Ubuntu 20.04/22.04/24.04 atau Debian 11/12." ;;
esac

# Nonaktifkan prompt interaktif apt
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# Fix dpkg interrupted (kalau VPS pernah gagal install sebelumnya)
info "Memperbaiki dpkg jika ada yang interrupted..."
dpkg --configure -a 2>/dev/null || true

# Update repo list dulu (wajib di fresh VPS)
info "Update package list..."
$PKG_MGR update -y 2>&1 | tail -3

# Install tool bootstrap yang PASTI dibutuhkan sebelum langkah lain
info "Install tool dasar (curl, wget, git, unzip, ca-certificates)..."
$PKG_MGR install -y \
  curl \
  wget \
  git \
  unzip \
  rsync \
  gnupg \
  ca-certificates \
  lsb-release \
  apt-transport-https \
  software-properties-common \
  net-tools \
  psmisc \
  iproute2 \
  cron \
  2>&1 | tail -5

ok "Bootstrap selesai."

# ── Input dari user ──────────────────────────────────────────
step "INPUT — Konfigurasi instalasi"

ask "Domain (contoh: ssm.sherif.eu.cc): "; read -r DOMAIN
[ -z "${DOMAIN:-}" ] && err "Domain tidak boleh kosong."

ask "Direktori install (default: /var/www/html/ssm): "; read -r WEBROOT
WEBROOT="${WEBROOT:-/var/www/html/ssm}"

ask "Nama database (default: ssm_db): "; read -r DB_NAME
DB_NAME="${DB_NAME:-ssm_db}"

ask "Username database (default: ssm_user): "; read -r DB_USER
DB_USER="${DB_USER:-ssm_user}"

ask "Password database baru: "; read -rs DB_PASS; echo ""
[ -z "${DB_PASS:-}" ] && err "Password database tidak boleh kosong."

echo ""
echo -e "${YELLOW}Password root MySQL:${NC}"
echo -e "  - Kosongkan jika VPS fresh install (MySQL belum punya password)"
echo -e "  - Isi jika sudah pernah set password root MySQL"
ask "Password root MySQL: "; read -rs MYSQL_ROOT_PASS; echo ""

echo ""
echo -e "${CYAN}${BOLD}Ringkasan konfigurasi:${NC}"
echo "  Domain  : $DOMAIN"
echo "  Webroot : $WEBROOT"
echo "  DB Name : $DB_NAME"
echo "  DB User : $DB_USER"
echo ""
ask "Lanjutkan? (y/n): "; read -r CONFIRM
[[ "${CONFIRM:-n}" != "y" && "${CONFIRM:-n}" != "Y" ]] && echo -e "${RED}Dibatalkan.${NC}" && exit 0

# ════════════════════════════════════════════
# STEP 1 — Install Apache, MySQL, PHP
# ════════════════════════════════════════════
step "STEP 1/7 — Install Apache2, MySQL, PHP 8.1"

# Upgrade sistem
info "Upgrade sistem..."
$PKG_MGR upgrade -y 2>&1 | tail -3

# Tambah repo PHP Ondrej (support Ubuntu 20/22/24 & Debian 11/12)
info "Menambahkan repository PHP Ondrej..."
if [ "$OS_NAME" = "ubuntu" ]; then
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php 2>&1 | tail -3 || \
    warn "Gagal tambah PPA Ondrej, akan coba pakai PHP bawaan repo."
elif [ "$OS_NAME" = "debian" ]; then
  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/sury-php.list
fi

$PKG_MGR update -y 2>&1 | tail -3

# Tentukan versi PHP terbaik yang tersedia
PHP_VER=""
for ver in 8.2 8.1 8.0 7.4; do
  if $PKG_MGR show "php${ver}" &>/dev/null 2>&1; then
    PHP_VER="$ver"
    break
  fi
done
[ -z "$PHP_VER" ] && PHP_VER="8.1"
info "Menggunakan PHP versi: $PHP_VER"

# Install semua paket
info "Menginstall paket (ini mungkin butuh beberapa menit)..."
$PKG_MGR install -y \
  apache2 \
  mysql-server \
  "php${PHP_VER}" \
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
  certbot \
  python3-certbot-apache \
  2>&1 | tail -10

# Set PHP default
update-alternatives --set php "/usr/bin/php${PHP_VER}" 2>/dev/null || true

# Verifikasi PHP
PHP_INSTALLED=$(php -r "echo PHP_VERSION;" 2>/dev/null || echo "")
[ -z "$PHP_INSTALLED" ] && err "PHP gagal diinstall. Cek koneksi internet VPS."
ok "PHP $PHP_INSTALLED terinstall."

# Verifikasi ekstensi wajib
info "Verifikasi PHP extensions..."
MISSING_EXTS=""
for ext in curl mbstring xml zip gd bcmath mysqli json opcache; do
  php -m 2>/dev/null | grep -qi "^${ext}$" || MISSING_EXTS="$MISSING_EXTS $ext"
done

if [ -n "$MISSING_EXTS" ]; then
  warn "Extension missing:$MISSING_EXTS — mencoba install ulang..."
  for ext in $MISSING_EXTS; do
    $PKG_MGR install -y "php${PHP_VER}-${ext}" 2>/dev/null || \
    $PKG_MGR install -y "php-${ext}" 2>/dev/null || \
    warn "Tidak bisa install php-${ext}, lanjut..."
  done
else
  ok "Semua PHP extensions tersedia."
fi

# ════════════════════════════════════════════
# STEP 2 — Konfigurasi Apache
# ════════════════════════════════════════════
step "STEP 2/7 — Konfigurasi Apache"

# Bebaskan port 80 jika dipakai proses lain (nginx, dll)
info "Cek port 80..."
if ss -tlnp 2>/dev/null | grep -q ':80 ' || netstat -tlnp 2>/dev/null | grep -q ':80 '; then
  warn "Port 80 sedang dipakai, mencoba bebaskan..."
  # Stop nginx jika ada
  systemctl stop nginx 2>/dev/null || true
  systemctl disable nginx 2>/dev/null || true
  # Kill proses lain yang pakai port 80
  fuser -k 80/tcp 2>/dev/null || true
  sleep 2
  ok "Port 80 dibebaskan."
fi

a2enmod rewrite headers ssl deflate expires 2>&1 | grep -v "already enabled" || true

cat > "/etc/apache2/sites-available/ssm.conf" << VHOST
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

# Test config dulu
apache2ctl configtest 2>&1
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
  systemctl enable apache2
  systemctl restart apache2
  sleep 2
  # Verifikasi Apache benar-benar running
  if systemctl is-active --quiet apache2; then
    ok "Apache berjalan untuk domain ${DOMAIN}."
  else
    # Coba start ulang sekali lagi
    systemctl start apache2 2>&1 || true
    sleep 2
    systemctl is-active --quiet apache2 && ok "Apache berjalan." || \
      err "Apache gagal start. Cek: journalctl -xeu apache2.service"
  fi
else
  err "Apache config error. Cek: apache2ctl configtest"
fi

# ════════════════════════════════════════════
# STEP 3 — Clone / Deploy file project
# ════════════════════════════════════════════
step "STEP 3/7 — Deploy file project ke ${WEBROOT}"

mkdir -p "$WEBROOT"

# Deteksi apakah script dijalankan dari hasil clone atau curl pipe
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

info "Source : $SCRIPT_DIR"
info "Target : $WEBROOT"

if [ "$SCRIPT_DIR" = "$WEBROOT" ]; then
  info "Script sudah berada di webroot, skip copy."
else
  # Cek apakah source punya file project (bukan folder kosong)
  if [ -f "$SCRIPT_DIR/connect.php" ]; then
    rsync -a --exclude='.git' "$SCRIPT_DIR/" "$WEBROOT/" 2>/dev/null || \
      cp -r "$SCRIPT_DIR/." "$WEBROOT/"
    ok "File project disalin ke $WEBROOT."
  else
    # Fallback: clone dari GitHub
    warn "File project tidak ditemukan di $SCRIPT_DIR."
    info "Mencoba clone dari GitHub..."
    if [ -d "$WEBROOT/.git" ]; then
      git -C "$WEBROOT" pull origin main 2>&1 | tail -3
    else
      git clone https://github.com/sheriflks/ssm.git "$WEBROOT" 2>&1 | tail -5
    fi
    ok "Project di-clone dari GitHub."
  fi
fi

# Set permission
chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"
[ -d "$WEBROOT/library/assets" ] && chmod -R 775 "$WEBROOT/library/assets"
[ -f "$WEBROOT/library/shenn.log" ] && chmod 664 "$WEBROOT/library/shenn.log"

ok "Permission file diset."

# ════════════════════════════════════════════
# STEP 4 — Setup MySQL
# ════════════════════════════════════════════
step "STEP 4/7 — Setup MySQL"

systemctl enable mysql
systemctl start mysql

# Tunggu MySQL siap (fresh install kadang butuh beberapa detik)
info "Menunggu MySQL siap..."
for i in $(seq 1 15); do
  if mysqladmin ping --silent 2>/dev/null; then
    break
  fi
  sleep 1
done

# Tentukan cara koneksi MySQL
# Fresh Ubuntu: MySQL pakai auth_socket, tidak perlu password
MYSQL_CMD=""
if mysql -u root --batch --silent -e "SELECT 1;" &>/dev/null 2>&1; then
  MYSQL_CMD="mysql -u root"
  info "Koneksi MySQL: auth_socket (tanpa password)"
elif [ -n "${MYSQL_ROOT_PASS:-}" ] && mysql -u root -p"${MYSQL_ROOT_PASS}" --batch --silent -e "SELECT 1;" &>/dev/null 2>&1; then
  MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASS}"
  info "Koneksi MySQL: password"
else
  # Coba via sudo (beberapa distro butuh ini)
  if sudo mysql -u root --batch --silent -e "SELECT 1;" &>/dev/null 2>&1; then
    MYSQL_CMD="sudo mysql -u root"
    info "Koneksi MySQL: sudo auth_socket"
  else
    err "Tidak bisa konek ke MySQL. Coba jalankan: sudo mysql_secure_installation"
  fi
fi

# Buat database dan user
$MYSQL_CMD --batch --silent << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

[ $? -ne 0 ] && err "Gagal membuat database/user MySQL."
ok "Database '${DB_NAME}' dan user '${DB_USER}' siap."

# ════════════════════════════════════════════
# STEP 5 — Import Database.sql
# ════════════════════════════════════════════
step "STEP 5/7 — Import Database.sql"

SQL_FILE="$WEBROOT/Database.sql"
[ ! -f "$SQL_FILE" ] && err "File Database.sql tidak ditemukan di ${WEBROOT}"

info "Mengimport Database.sql ke '${DB_NAME}'..."
$MYSQL_CMD --batch "${DB_NAME}" < "$SQL_FILE"
[ $? -ne 0 ] && err "Gagal import Database.sql."
ok "Database.sql berhasil diimport."

# ════════════════════════════════════════════
# STEP 6 — Update connect.php
# ════════════════════════════════════════════
step "STEP 6/7 — Update connect.php"

CONNECT="$WEBROOT/connect.php"
[ ! -f "$CONNECT" ] && err "connect.php tidak ditemukan di ${WEBROOT}"

# Escape karakter spesial untuk sed (/, &, \)
escape_sed() { printf '%s\n' "$1" | sed -e 's/[\/&\\]/\\&/g'; }

DB_USER_ESC=$(escape_sed "$DB_USER")
DB_PASS_ESC=$(escape_sed "$DB_PASS")
DB_NAME_ESC=$(escape_sed "$DB_NAME")

sed -i "s/'host'\s*=>\s*'[^']*'/'host' => 'localhost'/" "$CONNECT"
sed -i "s/'user'\s*=>\s*'[^']*'/'user' => '${DB_USER_ESC}'/" "$CONNECT"
sed -i "s/'pass'\s*=>\s*'[^']*'/'pass' => '${DB_PASS_ESC}'/" "$CONNECT"
sed -i "s/'name'\s*=>\s*'[^']*'/'name' => '${DB_NAME_ESC}'/" "$CONNECT"

# Verifikasi hasil edit
if grep -q "'name' => '${DB_NAME_ESC}'" "$CONNECT"; then
  ok "connect.php berhasil dikonfigurasi."
else
  warn "Verifikasi connect.php gagal, cek manual: $CONNECT"
fi

# ════════════════════════════════════════════
# STEP 7 — SSL via Certbot
# ════════════════════════════════════════════
step "STEP 7/7 — SSL (Let's Encrypt)"

ask "Setup SSL otomatis untuk ${DOMAIN}? (y/n): "; read -r SSL_CONFIRM
if [[ "${SSL_CONFIRM:-n}" == "y" || "${SSL_CONFIRM:-n}" == "Y" ]]; then

  # Pastikan Apache running sebelum certbot
  if ! systemctl is-active --quiet apache2; then
    warn "Apache tidak running, mencoba start ulang..."
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1
    systemctl start apache2 2>/dev/null || true
    sleep 2
  fi

  # Pastikan port 80 bisa diakses dari luar (cek DNS resolve ke IP ini)
  SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
              curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "unknown")
  DOMAIN_IP=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || echo "")

  if [ -n "$DOMAIN_IP" ] && [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    warn "DNS ${DOMAIN} mengarah ke ${DOMAIN_IP}, tapi IP VPS ini adalah ${SERVER_IP}."
    warn "SSL tidak bisa diproses sampai DNS propagate. Skip SSL untuk sekarang."
    warn "Jalankan manual setelah DNS propagate: certbot --apache -d ${DOMAIN}"
  else
    certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}" --redirect 2>&1
    if [ $? -eq 0 ]; then
      ok "SSL aktif untuk ${DOMAIN}."
    else
      warn "SSL gagal. Coba lagi setelah DNS propagate:"
      warn "  certbot --apache -d ${DOMAIN}"
    fi
  fi
else
  warn "SSL dilewati. Aktifkan manual: certbot --apache -d ${DOMAIN}"
fi

# ════════════════════════════════════════════
# BONUS — Cron Job
# ════════════════════════════════════════════
step "BONUS — Setup Cron Job"

systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true

CRON_STATUS="* * * * * /usr/bin/php ${WEBROOT}/library/cron/status-socmed.php > /dev/null 2>&1"
CRON_REFUND="* * * * * /usr/bin/php ${WEBROOT}/library/cron/refund-socmed.php > /dev/null 2>&1"

# Tambah cron hanya kalau belum ada
CURRENT_CRON=$(crontab -l 2>/dev/null || echo "")
NEW_CRON="$CURRENT_CRON"
echo "$CURRENT_CRON" | grep -qF "status-socmed" || NEW_CRON="${NEW_CRON}
${CRON_STATUS}"
echo "$CURRENT_CRON" | grep -qF "refund-socmed"  || NEW_CRON="${NEW_CRON}
${CRON_REFUND}"
echo "$NEW_CRON" | crontab -

ok "Cron job aktif."

# ════════════════════════════════════════════
# SELESAI
# ════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}================================================${NC}"
echo -e "${GREEN}${BOLD}  ✓  INSTALASI SELESAI!${NC}"
echo -e "${GREEN}${BOLD}================================================${NC}"
echo ""
echo -e "  URL     : ${CYAN}https://${DOMAIN}${NC}"
echo -e "  Webroot : ${CYAN}${WEBROOT}${NC}"
echo -e "  DB Name : ${CYAN}${DB_NAME}${NC}"
echo -e "  DB User : ${CYAN}${DB_USER}${NC}"
echo -e "  PHP     : ${CYAN}$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo 'unknown')${NC}"
echo ""
echo -e "${YELLOW}${BOLD}  Langkah selanjutnya:${NC}"
echo "  1. Buka https://${DOMAIN} di browser"
echo "  2. Login panel admin, konfigurasi:"
echo "     - SMTP (email notifikasi)"
echo "     - Payment gateway (Paydisini, dll)"
echo "     - Provider API (Digiflazz, dll)"
echo "     - Firebase Cloud Messaging"
echo ""
echo -e "${CYAN}  Cek log jika ada error:${NC}"
echo "  tail -f /var/log/apache2/ssm_error.log"
echo ""
