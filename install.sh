#!/bin/bash

# ============================================================
#   SSM - Installer Script for VPS
#   Target: ssm.sherif.eu.cc
#   Author: sheriflks
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
  echo -e "${CYAN}"
  echo "  ____  ____  __  __ "
  echo " / ___||  _ \|  \/  |"
  echo " \___ \| |_) | |\/| |"
  echo "  ___) |  __/| |  | |"
  echo " |____/|_|   |_|  |_|"
  echo -e "${NC}"
  echo -e "${GREEN}  SSM Panel - VPS Installer${NC}"
  echo "============================================"
  echo ""
}

print_banner

# ── Root check ───────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Jalankan sebagai root: sudo bash install.sh${NC}"
  exit 1
fi

# ── Input ────────────────────────────────────────────────────
echo -ne "${YELLOW}[?] Domain (contoh: ssm.sherif.eu.cc): ${NC}"
read DOMAIN

echo -ne "${YELLOW}[?] Direktori install (default: /var/www/html/ssm): ${NC}"
read WEBROOT
WEBROOT=${WEBROOT:-/var/www/html/ssm}

echo -ne "${YELLOW}[?] Nama database (default: ssm_db): ${NC}"
read DB_NAME
DB_NAME=${DB_NAME:-ssm_db}

echo -ne "${YELLOW}[?] Username database (default: ssm_user): ${NC}"
read DB_USER
DB_USER=${DB_USER:-ssm_user}

echo -ne "${YELLOW}[?] Password database baru: ${NC}"
read -s DB_PASS
echo ""

echo -ne "${YELLOW}[?] Password root MySQL (kosongkan jika pakai auth_socket): ${NC}"
read -s MYSQL_ROOT_PASS
echo ""

# Tentukan cara koneksi MySQL
if [ -z "$MYSQL_ROOT_PASS" ]; then
  MYSQL_CMD="mysql -u root"
else
  MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASS}"
fi

echo ""
echo -e "${CYAN}[INFO] Konfigurasi:${NC}"
echo "  Domain  : $DOMAIN"
echo "  Webroot : $WEBROOT"
echo "  DB Name : $DB_NAME"
echo "  DB User : $DB_USER"
echo ""
echo -ne "${YELLOW}[?] Lanjutkan? (y/n): ${NC}"
read CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${RED}Dibatalkan.${NC}"
  exit 0
fi

# ── 1. Install paket ─────────────────────────────────────────
echo -e "\n${CYAN}[1/7] Install dependensi...${NC}"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 mysql-server \
  php php-mysql php-curl php-mbstring php-xml php-zip php-gd php-bcmath \
  unzip curl git certbot python3-certbot-apache python3
echo -e "${GREEN}[OK] Dependensi terinstall.${NC}"

# ── 2. Apache config ─────────────────────────────────────────
echo -e "\n${CYAN}[2/7] Konfigurasi Apache...${NC}"
a2enmod rewrite headers ssl

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

    ErrorLog \${APACHE_LOG_DIR}/ssm_error.log
    CustomLog \${APACHE_LOG_DIR}/ssm_access.log combined
</VirtualHost>
VHOST

a2ensite ssm.conf
a2dissite 000-default.conf 2>/dev/null || true
systemctl enable apache2
systemctl restart apache2
echo -e "${GREEN}[OK] Apache dikonfigurasi.${NC}"

# ── 3. Deploy file ───────────────────────────────────────────
echo -e "\n${CYAN}[3/7] Deploy file project ke ${WEBROOT}...${NC}"
mkdir -p "$WEBROOT"

# Deteksi lokasi script (support curl pipe maupun file langsung)
if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "bash" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

if [ "$SCRIPT_DIR" != "$WEBROOT" ]; then
  rsync -a --exclude='.git' "$SCRIPT_DIR/" "$WEBROOT/" 2>/dev/null || \
    cp -r "$SCRIPT_DIR/." "$WEBROOT/"
fi

chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"
[ -d "$WEBROOT/library/assets" ] && chmod -R 775 "$WEBROOT/library/assets"
echo -e "${GREEN}[OK] File project di-deploy.${NC}"

# ── 4. Setup MySQL ───────────────────────────────────────────
echo -e "\n${CYAN}[4/7] Setup database MySQL...${NC}"
systemctl enable mysql
systemctl start mysql

# Jalankan query setup DB
$MYSQL_CMD --batch --silent << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ $? -ne 0 ]; then
  echo -e "${RED}[ERROR] Gagal setup database.${NC}"
  exit 1
fi
echo -e "${GREEN}[OK] Database '${DB_NAME}' siap.${NC}"

# ── 5. Import Database.sql ───────────────────────────────────
echo -e "\n${CYAN}[5/7] Import Database.sql...${NC}"
SQL_FILE="$WEBROOT/Database.sql"

if [ ! -f "$SQL_FILE" ]; then
  echo -e "${RED}[ERROR] File Database.sql tidak ditemukan di ${WEBROOT}${NC}"
  exit 1
fi

$MYSQL_CMD --batch "${DB_NAME}" < "$SQL_FILE"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}[OK] Database.sql berhasil diimport ke '${DB_NAME}'.${NC}"
else
  echo -e "${RED}[ERROR] Gagal import Database.sql.${NC}"
  exit 1
fi

# ── 6. Update connect.php ────────────────────────────────────
echo -e "\n${CYAN}[6/7] Update connect.php...${NC}"
CONNECT="$WEBROOT/connect.php"

if [ ! -f "$CONNECT" ]; then
  echo -e "${RED}[ERROR] connect.php tidak ditemukan.${NC}"
  exit 1
fi

# Escape karakter spesial untuk sed
DB_USER_ESC=$(printf '%s\n' "$DB_USER" | sed 's/[[\.*^$()+?{|]/\\&/g')
DB_PASS_ESC=$(printf '%s\n' "$DB_PASS" | sed 's/[[\.*^$()+?{|]/\\&/g; s/\//\\\//g')
DB_NAME_ESC=$(printf '%s\n' "$DB_NAME" | sed 's/[[\.*^$()+?{|]/\\&/g')

sed -i "s/'host'\s*=>\s*'[^']*'/'host' => 'localhost'/" "$CONNECT"
sed -i "s/'user'\s*=>\s*'[^']*'/'user' => '${DB_USER_ESC}'/" "$CONNECT"
sed -i "s/'pass'\s*=>\s*'[^']*'/'pass' => '${DB_PASS_ESC}'/" "$CONNECT"
sed -i "s/'name'\s*=>\s*'[^']*'/'name' => '${DB_NAME_ESC}'/" "$CONNECT"

echo -e "${GREEN}[OK] connect.php dikonfigurasi.${NC}"

# ── 7. SSL via Certbot ───────────────────────────────────────
echo -e "\n${CYAN}[7/7] Setup SSL (Let's Encrypt)...${NC}"
echo -ne "${YELLOW}[?] Setup SSL otomatis untuk ${DOMAIN}? (y/n): ${NC}"
read SSL_CONFIRM
if [[ "$SSL_CONFIRM" == "y" || "$SSL_CONFIRM" == "Y" ]]; then
  certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}" --redirect
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] SSL aktif untuk ${DOMAIN}.${NC}"
  else
    echo -e "${YELLOW}[WARN] SSL gagal. Pastikan DNS sudah mengarah ke IP VPS ini.${NC}"
  fi
else
  echo -e "${YELLOW}[SKIP] SSL dilewati. Aktifkan manual: certbot --apache -d ${DOMAIN}${NC}"
fi

# ── Setup Cron ───────────────────────────────────────────────
echo -e "\n${CYAN}[+] Setup cron job...${NC}"
CRON_STATUS="* * * * * php ${WEBROOT}/library/cron/status-socmed.php > /dev/null 2>&1"
CRON_REFUND="* * * * * php ${WEBROOT}/library/cron/refund-socmed.php > /dev/null 2>&1"

(crontab -l 2>/dev/null | grep -qF "status-socmed") || \
  (crontab -l 2>/dev/null; echo "$CRON_STATUS") | crontab -
(crontab -l 2>/dev/null | grep -qF "refund-socmed") || \
  (crontab -l 2>/dev/null; echo "$CRON_REFUND") | crontab -

echo -e "${GREEN}[OK] Cron job ditambahkan.${NC}"

# ── Selesai ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  INSTALASI SELESAI!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  URL     : ${CYAN}https://${DOMAIN}${NC}"
echo -e "  Webroot : ${CYAN}${WEBROOT}${NC}"
echo -e "  DB Name : ${CYAN}${DB_NAME}${NC}"
echo -e "  DB User : ${CYAN}${DB_USER}${NC}"
echo ""
echo -e "${YELLOW}  Langkah selanjutnya:${NC}"
echo "  1. Buka https://${DOMAIN} di browser"
echo "  2. Login panel admin & konfigurasi SMTP, payment gateway, provider"
echo "  3. Cron job sudah aktif otomatis"
echo ""
