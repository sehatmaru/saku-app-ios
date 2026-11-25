# Fondasi

Sumber kode: `App/Core/DesignSystem/AppColor.swift`, `Spacing.swift`, `App/Shared/Extensions/Font+App.swift`, `App/Shared/Components/PocketLogo.swift` (gerak), `App/Shared/Components/AppTabBar.swift` (haptik).

## Warna

Semua lewat `Color.app...`. Pasangan (terang / gelap), kecuali dicatat lain.

| Token | Terang | Gelap | Pakai untuk |
|---|---|---|---|
| `appPrimary` | #16875A | #2FB57C | Tombol utama, aksi, pemasukan, centang pilihan |
| `appPrimaryText` | #0F6B47 | #2FB57C | Teks hijau kecil di atas chip hijau (kontras 4.5:1) |
| `appBrand` | #16875A | #16875A | Latar splash, login, logo (tetap, tidak berubah di gelap) |
| `appSecondary` | #1FA06B | #3FC98C | Hijau pendukung |
| `appSuccess` | = `appPrimary` | | Status berhasil |
| `appWarning` | #C4610A | #F0913A | Peringatan |
| `appError` | #D93636 | #FF5C5C | Galat, tindakan merusak, hitungan hapus |
| `appText` | #111111 | #F5F5F7 | Teks utama |
| `appBody` | #3A3A3C | #D1D1D6 | Teks isi panjang |
| `appTextSecondary` | #6E6E73 | #98989D | Keterangan, subjudul |
| `appTextTertiary` | #A1A1A6 | #636366 | Placeholder, chevron, penunjuk lemah |
| `appBackground` | sistem | sistem | Latar halaman |
| `appGroupedBackground` | sistem | sistem | Latar halaman berkelompok |
| `appCardBackground` | sistem | sistem | Latar kartu berkelompok |
| `appFill` | #F2F2F4 | #1C1C1E | Isian abu: kartu pilihan, kolom cari, tombol bulat |
| `appSheetField` | #F2F2F4 | #2C2C2E | Kotak di dalam sheet (kode undangan, info) |
| `appSeparator` | #F2F2F4 | #2C2C2E | Pemisah baris di daftar |
| `appDivider` | #EDEDF0 | #38383A | Pemisah seksi, jalur progres |
| `appBorder` | #D2D2D7 | #48484A | Garis tepi tipis (dipakai hemat) |
| `appInvestment` | #946200 | #E0A93B | Dompet investasi |
| `appInvestmentTint` | #FBF3E2 | #2A2415 | Latar lembut investasi |
| `appInvestmentPanel` | #946200 | #946200 | Panel emas di belakang teks putih |
| `appIncome` | = `appPrimary` | | Nominal pemasukan |
| `appExpense` | = `appText` | | Nominal pengeluaran (netral, bukan merah) |

Aturan:
- Hanya pemasukan yang diwarnai. Pengeluaran tetap warna teks.
- Teks di atas warna isian memakai warna teks, bukan hijau, kecuali chip hijau (`appPrimaryText`).
- Tint status (notice, sheet): warna nada pada sekitar 9% opasitas; lihat `components.md` (NoticeCard, SmartSheetTone).
- Tidak ada gradien dan bayangan sebagai hiasan.

## Tipografi

Satu fungsi: `Font.app(size, weight:)` (system font, SF). Wordmark saja yang memakai `Font.wordmark` (Plus Jakarta Sans ExtraBold, `Resources/Fonts/PlusJakartaSans.ttf`).

Ukuran yang terpakai di kode, dan perannya:

| Ukuran | Bobot umum | Peran | Catatan pemakaian |
|---|---|---|---|
| 44 | bold | Angka hero (saldo) | `HeroAmount`, 11 pemakaian |
| 34 | bold | Kode undangan, angka besar | mono bila kode |
| 28 | bold | Judul layar hasil (sukses) | |
| 30 | bold | Judul langkah wizard | `header(...)` di wizard |
| 22 | bold | Judul sheet | 59 pemakaian, `tracking(-0.3)` |
| 20 | semibold | Judul seksi besar, ikon baris | |
| 17 | semibold | Tombol utama, nilai baris | |
| 16 | regular / semibold | Isi utama, judul baris | |
| 15 | regular / semibold | Isi, subjudul halaman, tombol kedua | |
| 14 | regular | Isi kecil, subjudul baris | |
| 13 | regular / semibold | Keterangan, caption seksi | ukuran paling sering |
| 12 | regular | Keterangan kecil, lencana | |
| 11 | regular | Label sangat kecil | gunakan hemat |

Aturan: satu ukuran tampilan per layar; angka yang berubah memakai `monospacedDigit`/`CountingText`; judul besar memakai `tracking(-0.3)`; Dynamic Type harus tetap terbaca (lihat `findings.md`, ukuran tetap).

## Jarak

`Spacing`: xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, xxxl 40, huge 48.

Pola berulang:
- Gutter layar kiri-kanan: **24** (`xl`).
- Jarak antar kartu atau pilihan: **12** (`md`).
- Isi dalam kartu: horizontal **16**, vertikal 12-20.
- Tinggi baris daftar: 48-68 (baris Profil minimal 48, baris Workspace 68).
- Tinggi tombol: **52** (utama), area ketuk minimal **44**.
- Ruang bawah di atas tombol bawah layar: 8 atas, 12 bawah; ruang bawah daftar bertab 96 (menyisakan tombol ✦ mengambang).

## Radius

| Radius | Untuk |
|---|---|
| Kapsul (setengah tinggi) | Tombol, chip, lencana |
| 24 | `NoticeCard` |
| 20 | Kartu pilihan besar, tiket kode |
| 16 | Kartu isian abu, baris pilihan (paling sering, 71 pemakaian) |
| 14 | Kolom isian, kartu info |
| 12 | Kisi ikon, kotak kecil |
| 10 | Chip kecil |
| 29% sisi, `.continuous` | Badge Workspace (squircle) |

Aturan: selalu `style: .continuous` untuk sudut membulat. Jangan memakai radius di luar skala ini tanpa mengubah dokumen.

## Gerak

- Kurva bersama: `Animation.settle(d)` = cubic-bezier(.2,.9,.25,1). Durasi umum 0.3 (paling sering), 0.4, 0.42, 0.5.
- `easeOut(0.2)` untuk perubahan kecil (status, warna).
- Pegas hanya untuk benda yang digerakkan jari atau muncul (`spring(duration: 0.48, bounce: 0.35)` di toast).
- Muncul: `rise(...)` dan `stEnter(index)` (naik dan memudar, berurutan).
- Tekan: `PressScaleStyle` (tombol, kartu) dan `RowPressStyle` (baris daftar: sorotan latar, tidak mengecil).
- Goyang untuk galat isian: `ShakeEffect` (`SetupSteps.swift`).
- Hormati Reduce Motion: gerak ruang berubah menjadi pudar.
- Pintu frekuensi: tab, keyboard, scroll memakai bawaan sistem; jangan dianimasikan ulang.

## Haptik

- `Haptics.add()` impact medium (buka form tambah), `welcome()` success, `logout()` warning (`AppTabBar.swift`).
- Pilihan: `UISelectionFeedbackGenerator` (kartu pilihan, tile ikon).
- Hasil: `UINotificationFeedbackGenerator` success/error (simpan, galat validasi).
- Konfirmasi tahan: `UIImpactFeedbackGenerator(.rigid)`.
- Satu haptik per aksi, bersamaan dengan visual, tidak pernah satu-satunya umpan balik.
