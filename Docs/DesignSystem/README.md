# Saku design system

Sumber kebenaran untuk tampilan Saku (iOS). Semua nilai di sini dicatat dari kode yang ada; kalau dokumen dan kode berbeda, kode menang dan dokumen diperbaiki.

## Isi

| File | Isi |
|---|---|
| [foundations.md](foundations.md) | Warna, tipografi, jarak, radius, gerak, haptik |
| [identity-icons.md](identity-icons.md) | Logo, ikon app, SF Symbols, avatar, badge |
| [components.md](components.md) | Tombol, isian, baris, kartu, umpan balik, data, navigasi |
| [sheets-pages.md](sheets-pages.md) | Sheet, dialog, pola halaman, wizard, layar hasil |
| [content.md](content.md) | Bahasa, istilah baku, nada, format, status kosong dan gagal |
| [findings.md](findings.md) | Inkonsistensi yang ditemukan saat audit (belum diperbaiki) |

Kanvas visual: Artifact "Saku design system" https://claude.ai/artifact/Uxo5YKbSaKmTDiGgdQojZE (privat; dibuat dari kode, bukan sumber kebenaran). Galeri komponen asli di app: Profil > Menu uji > Galeri komponen (hanya build DEBUG/internal).

## Prinsip

1. **Tenang dan minimal.** Netral dulu, hijau hanya untuk aksi utama, pemasukan, dan status baik. Pengeluaran tetap netral (`appExpense` = warna teks).
2. **Sedikit garis, sedikit teks.** Pisahkan dengan jarak dan isian abu, bukan garis. Satu pesan cukup satu kali.
3. **Terang dan gelap bersamaan.** Semua warna lewat token berpasangan; jangan hex lepas di tampilan.
4. **Pakai yang sudah ada.** Sheet = `SmartSheet`/`filterSheet`, tombol = komponen di bawah. Jangan membuat versi sendiri.
5. **Teks Indonesia adalah kunci.** Setiap string baru masuk katalog (lihat `content.md`).
6. **Gerak punya tujuan.** Umpan balik, perubahan status, kesinambungan ruang. Hormati Reduce Motion.

## Cara memakai dokumen ini

- Sebelum membuat layar, sheet, atau komponen: baca `foundations.md` dan `components.md`.
- Komponen baru yang dipakai di lebih dari satu layar: taruh di `App/Shared/Components/`, tambahkan ke `components.md` dan ke galeri DEBUG.
- Nilai baru (warna, ukuran huruf, radius) hanya boleh ditambahkan lewat perubahan dokumen ini lebih dulu.
- Aturan antislop (`.claude/skills/antislop*`) tetap berlaku di atas dokumen ini.
