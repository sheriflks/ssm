#!/bin/bash

# ============================================================
#   SSM - Installer Script for VPS
#   Target: ssm.sherif.eu.cc
#   Author: sheriflks
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Jalankan sebagai root: sudo bash install.sh${NC}"
  exit 1
fi

# ── Input ────────────────────────────────────────────────────
read -p "$(echo -e ${YELLOW}[?] Domain (contoh: ssm.sherif.eu.cc): ${NC})" DOMAIN
read -p "$(echo -e ${YELLOW}[?] Direktori install (default: /var/www/html/ssm): ${NC})" WEBROOT
WEBROOT=${WEBROOT:-/var/www/html/ssm}
read -p "$(echo -e ${YELLOW}[?] Nama database (default: ssm_db): ${NC})" DB_NAME
DB_NAME=${DB_NAME:-ssm_db}
read -p "$(echo -e ${YELLOW}[?] Username database (default: ssm_user): ${NC})" DB_USER
DB_USER=${DB_USER:-ssm_user}
read -s -p "$(echo -e ${YELLOW}[?] Password database baru: ${NC})" DB_PASS
echo ""
read -s -p "$(echo -e ${YELLOW}[?] Password root MySQL: ${NC})" MYSQL_ROOT_PASS
echo ""

echo ""
echo -e "${CYAN}[INFO] Konfigurasi:${NC}"
echo "  Domain  : $DOMAIN"
echo "  Webroot : $WEBROOT"
echo "  DB Name : $DB_NAME"
echo "  DB User : $DB_USER"
echo ""
read -p "$(echo -e ${YELLOW}[?] Lanjutkan? (y/n): ${NC})" CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo -e "${RED}Dibatalkan.${NC}" && exit 0

# ── 1. Install paket ─────────────────────────────────────────
echo -e "\n${CYAN}[1/7] Install dependensi...${NC}"
apt-get update -y
apt-get install -y apache2 mysql-server php php-mysql php-curl php-mbstring \
  php-xml php-zip php-gd php-bcmath unzip curl git certbot python3-certbot-apache

# ── 2. Apache config ─────────────────────────────────────────
echo -e "\n${CYAN}[2/7] Konfigurasi Apache...${NC}"
a2enmod rewrite headers ssl

VHOST_FILE="/etc/apache2/sites-available/ssm.conf"
cat > "$VHOST_FILE" <<VHOST
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $WEBROOT

    <Directory $WEBROOT>
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
systemctl restart apache2
echo -e "${GREEN}[OK] Apache dikonfigurasi.${NC}"

# ── 3. Deploy file ───────────────────────────────────────────
echo -e "\n${CYAN}[3/7] Deploy file project ke $WEBROOT...${NC}"
mkdir -p "$WEBROOT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$SCRIPT_DIR" != "$WEBROOT" ]; then
  cp -r "$SCRIPT_DIR"/. "$WEBROOT"/
fi

chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"
chmod -R 775 "$WEBROOT/library/assets" 2>/dev/null || true
echo -e "${GREEN}[OK] File project di-deploy.${NC}"

# ── 4. Setup database ────────────────────────────────────────
echo -e "\n${CYAN}[4/7] Setup database MySQL...${NC}"
mysql -u root -p"$MYSQL_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ $? -ne 0 ]; then
  echo -e "${RED}[ERROR] Gagal setup database. Cek password root MySQL.${NC}"
  exit 1
fi
echo -e "${GREEN}[OK] Database '$DB_NAME' siap.${NC}"

# ── 5. Import Database.sql ───────────────────────────────────
echo -e "\n${CYAN}[5/7] Import Database.sql...${NC}"
SQL_FILE="$WEBROOT/Database.sql"

if [ ! -f "$SQL_FILE" ]; then
  echo -e "${RED}[ERROR] File Database.sql tidak ditemukan di $WEBROOT${NC}"
  exit 1
fi

mysql -u root -p"$MYSQL_ROOT_PASS" "$DB_NAME" < "$SQL_FILE"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}[OK] Database.sql berhasil diimport ke '$DB_NAME'.${NC}"
else
  echo -e "${RED}[ERROR] Gagal import Database.sql.${NC}"
  exit 1
fi

# ── 6. Update connect.php ────────────────────────────────────
echo -e "\n${CYAN}[6/7] Update connect.php...${NC}"
CONNECT="$WEBROOT/connect.php"

python3 - <<PYEOF
import re

with open('$CONNECT', 'r') as f:
    content = f.read()

content = re.sub(r"'host'\s*=>\s*'[^']*'", "'host' => 'localhost'", content)
content = re.sub(r"'user'\s*=>\s*'[^']*'", "'user' => '$DB_USER'", content)
content = re.sub(r"'pass'\s*=>\s*'[^']*'", "'pass' => '$DB_PASS'", content)
content = re.sub(r"'name'\s*=>\s*'[^']*'", "'name' => '$DB_NAME'", content)

with open('$CONNECT', 'w') as f:
    f.write(content)

print("connect.php updated.")
PYEOF

echo -e "${GREEN}[OK] connect.php dikonfigurasi.${NC}"

# ── 7. SSL via Certbot ───────────────────────────────────────
echo -e "\n${CYAN}[7/7] Setup SSL (Let's Encrypt)...${NC}"
read -p "$(echo -e ${YELLOW}[?] Setup SSL otomatis untuk $DOMAIN? (y/n): ${NC})" SSL_CONFIRM
if [[ "$SSL_CONFIRM" == "y" || "$SSL_CONFIRM" == "Y" ]]; then
  certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --redirect
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] SSL aktif untuk $DOMAIN.${NC}"
  else
    echo -e "${YELLOW}[WARN] SSL gagal. Pastikan DNS domain sudah mengarah ke VPS ini.${NC}"
  fi
else
  echo -e "${YELLOW}[SKIP] SSL dilewati. Aktifkan manual dengan: certbot --apache -d $DOMAIN${NC}"
fi

# ── Selesai ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  INSTALASI SELESAI!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  URL     : ${CYAN}https://$DOMAIN${NC}"
echo -e "  Webroot : ${CYAN}$WEBROOT${NC}"
echo -e "  DB Name : ${CYAN}$DB_NAME${NC}"
echo -e "  DB User : ${CYAN}$DB_USER${NC}"
echo ""
echo -e "${YELLOW}  Langkah selanjutnya:${NC}"
echo "  1. Login ke panel admin"
echo "  2. Konfigurasi SMTP, payment gateway, dan provider"
echo "  3. Pastikan cron job aktif:"
echo -e "     ${CYAN}* * * * * php $WEBROOT/library/cron/status-socmed.php${NC}"
echo -e "     ${CYAN}* * * * * php $WEBROOT/library/cron/refund-socmed.php${NC}"
echo ""
