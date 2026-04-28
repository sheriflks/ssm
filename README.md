# SSM - Social Media Store / SMM Panel

Platform SMM (Social Media Marketing) berbasis PHP untuk jual beli layanan sosial media, pulsa, dan tagihan.

## Fitur

- Order layanan sosial media (followers, likes, views, dll)
- Pembelian pulsa & paket data (via Digiflazz)
- Pembayaran tagihan postpaid
- Sistem deposit & voucher
- Multi payment gateway (Paydisini, dll)
- Notifikasi via Firebase, WhatsApp (Atlantic), Email (SMTP)
- Panel admin lengkap
- REST API untuk integrasi pihak ketiga
- Sistem referral & poin
- Laporan & export Excel

## Requirement

- PHP >= 7.4 (rekomendasi PHP 8.1+)
- MySQL / MariaDB >= 5.7
- Apache2 dengan mod_rewrite aktif
- Composer (opsional)
- SSL/HTTPS (wajib untuk produksi)

## Instalasi Cepat di VPS

```bash
bash <(curl -s https://raw.githubusercontent.com/sheriflks/ssm/main/install.sh)
```

Atau clone manual:

```bash
git clone https://github.com/sheriflks/ssm.git /var/www/html/ssm
cd /var/www/html/ssm
bash install.sh
```

## Konfigurasi

Edit file `connect.php` setelah instalasi:

```php
$aiy = [
    'host' => 'localhost',
    'user' => 'YOUR_DB_USER',
    'pass' => 'YOUR_DB_PASS',
    'name' => 'YOUR_DB_NAME'
];
```

## Struktur Direktori

```
ssm/
├── account/        # Halaman akun pengguna
├── admin/          # Panel administrasi
├── api/            # REST API endpoint
├── auth/           # Login, register, forgot password
├── callback/       # Callback payment gateway
├── deposit/        # Sistem deposit
├── landing/        # Halaman landing page
├── library/        # Core library & fungsi
├── order/          # Halaman order
├── page/           # Halaman statis
├── premium/        # Fitur premium
├── connect.php     # Konfigurasi database & bootstrap
└── index.php       # Entry point utama
```

## Domain

Setelah instalasi, arahkan domain ke direktori project dan pastikan SSL aktif.

Target domain: `ssm.sherif.eu.cc`

## Lisensi

Private - All rights reserved.
