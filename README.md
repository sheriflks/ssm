# SSM Panel

Platform SMM (Social Media Marketing) berbasis PHP — jual beli layanan sosial media, pulsa, dan tagihan.

---

## Deploy ke cPanel — Cara Cepat

### 1. Buat Database di cPanel

1. Login cPanel → **MySQL Databases**
2. Buat database baru → contoh: `sherif_ssm`
3. Buat user baru → contoh: `sherif_ssmuser` + password
4. Tambahkan user ke database → **All Privileges**

> Di cPanel, nama database & user selalu diawali prefix username cPanel.
> Contoh username cPanel `sherif` → DB = `sherif_ssm`, user = `sherif_ssmuser`

---

### 2. Upload File

**Via File Manager cPanel:**
1. cPanel → **File Manager** → masuk ke folder domain kamu
   - Untuk domain utama: `public_html/`
   - Untuk subdomain `ssm.sherif.eu.cc`: `public_html/ssm/` atau folder subdomain
2. Klik **Upload** → upload semua file project (bisa ZIP dulu lalu extract)
3. Pastikan struktur file langsung di dalam folder domain, bukan di subfolder lagi

**Via FTP (FileZilla):**
1. Host: domain/IP, Username & Password: dari cPanel → FTP Accounts
2. Upload semua file ke folder domain

---

### 3. Import Database

1. cPanel → **phpMyAdmin**
2. Klik nama database di panel kiri (`sherif_ssm`)
3. Tab **Import** → pilih file `Database.sql` → klik **Go**

---

### 4. Konfigurasi Database — 2 Cara

**Cara A — Pakai cpanel-config.php (Termudah):**

1. Edit file `cpanel-config.php` di File Manager:
```php
define('DB_USER', 'sherif_ssmuser');
define('DB_PASS', 'passwordkamu');
define('DB_NAME', 'sherif_ssm');
```
2. Buka di browser: `https://ssm.sherif.eu.cc/cpanel-config.php`
3. Kalau muncul ✅ → selesai, file otomatis terhapus

**Cara B — Edit connect.php Manual:**

Buka `connect.php` di File Manager, cari bagian ini dan isi:
```php
$aiy = [
    'host' => 'localhost',
    'user' => 'sherif_ssmuser',  // ← ganti ini
    'pass' => 'passwordkamu',    // ← ganti ini
    'name' => 'sherif_ssm'       // ← ganti ini
];
```

---

### 5. Aktifkan SSL

1. cPanel → **SSL/TLS Status** → klik **Run AutoSSL**
2. Tunggu beberapa menit
3. Buka `https://ssm.sherif.eu.cc` — harus bisa diakses via HTTPS

---

### 6. Setup Cron Job

1. cPanel → **Cron Jobs**
2. Set ke **Once Per Minute (`* * * * *`)**
3. Tambahkan 2 command ini:

```
/usr/local/bin/php /home/USERNAME/public_html/library/cron/status-socmed.php >/dev/null 2>&1
```
```
/usr/local/bin/php /home/USERNAME/public_html/library/cron/refund-socmed.php >/dev/null 2>&1
```

> Ganti `USERNAME` dengan username cPanel kamu.
> Kalau tidak tahu path PHP, cek di cPanel → **Terminal** → ketik `which php`

---

### 7. Verifikasi

Buka `https://ssm.sherif.eu.cc` di browser.

- Muncul halaman login → ✅ **Berhasil**
- Muncul error 500 → lihat bagian Troubleshooting di bawah

---

## Konfigurasi Admin Setelah Install

Login ke panel admin dan isi:

| Menu | Yang Diisi |
|------|-----------|
| Config → Website | Nama site, deskripsi, icon |
| Config → SMTP | Host, user, password email |
| Config → Payment | API key Paydisini |
| Config → Firebase | Server key, Sender ID |
| Provider | Digiflazz username & API key |

---

## Troubleshooting

**HTTP 500 Error**
- Penyebab paling umum: `connect.php` belum dikonfigurasi
- Cek: cPanel → **Errors** (di bagian Logs)
- Pastikan nama DB, user, pass sudah benar dan sesuai prefix cPanel

**Halaman blank / tidak load**
- Pastikan `.htaccess` terupload (file hidden, aktifkan "Show Hidden Files" di File Manager)
- Pastikan PHP versi 7.4+ di cPanel → **MultiPHP Manager**

**Redirect loop HTTPS**
- Pastikan SSL sudah aktif sebelum buka site
- Kalau masih loop, nonaktifkan sementara baris HTTPS redirect di `.htaccess`

**Login tidak bisa**
- Pastikan database sudah diimport (cek tabel `users` ada di phpMyAdmin)
- Pastikan SSL aktif (login butuh HTTPS)

**Cron tidak jalan**
- Cek path PHP: cPanel → Terminal → `which php`
- Ganti `/usr/local/bin/php` dengan path yang benar

---

## Deploy ke VPS (Ubuntu/Debian)

```bash
git clone https://github.com/sheriflks/ssm.git /var/www/html/ssm
sudo bash /var/www/html/ssm/install.sh
```

---

## Struktur Direktori

```
ssm/
├── account/        # Halaman akun user
├── admin/          # Panel admin
├── api/            # REST API
├── auth/           # Login, register, forgot
├── callback/       # Callback payment gateway
├── deposit/        # Sistem deposit
├── landing/        # Landing page
├── library/        # Core library
│   ├── assets/     # CSS, JS, gambar
│   ├── cron/       # Script cron job
│   ├── function/   # Class & helper
│   ├── layout/     # Template header/footer
│   └── session/    # Session handler
├── order/          # Halaman order
├── page/           # Halaman statis
├── premium/        # Fitur premium
├── .htaccess       # Apache config & security
├── connect.php     # ← KONFIGURASI DATABASE DI SINI
├── cpanel-config.php  # Helper setup otomatis (hapus setelah dipakai)
├── Database.sql    # File database
└── install.sh      # Auto installer VPS
```

---

## Requirements

| Komponen | Versi |
|----------|-------|
| PHP | 7.4+ (rekomendasi 8.1) |
| MySQL / MariaDB | 5.7+ |
| Apache | 2.4+ dengan mod_rewrite |
| SSL | Wajib aktif |

**PHP Extensions:** `mysqli`, `curl`, `mbstring`, `xml`, `zip`, `gd`, `bcmath`, `json`, `opcache`
