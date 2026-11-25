# Temuan audit

Inkonsistensi yang ditemukan saat menyusun dokumen ini. Belum diperbaiki; tiap butir perlu keputusan sebelum diubah (alur kerja biasa: varian visual dulu, lalu uji di Zahard).

| # | Temuan | Dampak | Usulan |
|---|---|---|---|
| 1 | Wizard Tambah Workspace punya grup tombol sendiri (`ratioRow`, `secondaryButton`, `primaryButton`) yang menduplikasi `SmartSheetFooter` | Dua implementasi grup tombol 1 : 3; tinggi 52 vs 50, warna teks kiri berbeda | Selesai: wizard memakai `SmartSheetFooter` (belum diuji di Zahard) |
| 2 | Hex lepas di tampilan: sekitar 200 baris memakai `Color(hex:)` atau `Color(light: 0x...)` di luar `AppColor.swift` (Dashboard, Smart Tracker, wizard, sheet) | Warna tidak punya nama, sulit dijaga di mode gelap | Beri nama token untuk yang berulang, sisanya dibiarkan bila satu kali pakai dan beralasan |
| 3 | Merah galat ditulis ulang: `Color(hex: "D93636")` di `SmartSheetFooter` padahal `appError` bernilai #D93636 (terang) | Gelap memakai warna yang salah | Pakai `appError` |
| 4 | Radius di luar skala: 24 (14x), 18 (12x), 4, 28, 8, 5, 7, 32, 22 | Skala dokumen: 24, 20, 16, 14, 12, 10, kapsul | Tetapkan skala final lalu rapikan; 32 dan 22 mungkin badge, 28 kartu tahan |
| 5 | Ukuran huruf tetap: `Font.app` memakai `.system(size:)`, jadi tidak ikut Dynamic Type; ada ratusan `.font(.system(size: ...))` | Teks tidak membesar untuk pengguna dengan huruf besar | Pertimbangkan `relativeTo:` atau `@ScaledMetric` pada ukuran isi |
| 6 | `appTextFieldStyle()` (abu sistem, radius 12) bertentangan dengan isian wizard (`appFill`, radius 14, tinggi 54) | Dua gaya isian | Satu gaya isian bersama |
| 7 | `WorkspaceBadge` lingkaran di daftar, squircle di wizard | Bentuk badge Workspace berbeda antar layar | Satu bentuk (squircle) |
| 8 | Judul layar: `ScreenHeader` 34 vs judul navigasi tengah 17 di halaman detail | Dua pola judul | Dokumentasikan sebagai dua pola sah, atau samakan |
| 9 | Tombol bulat dengan latar `appFill` (17 pemakaian `appFill, in: Capsule`) bercampur dengan tombol kedua yang kini teks saja | Pemakaian tombol berlatar abu masih ada di tempat lain | Tinjau satu per satu: aksi sekunder penuh lebar jadi teks, tombol bulat ikon boleh tetap |
| 10 | Komponen pilihan (`choiceCard`) dan kolom isian nama hidup lokal di wizard | Tidak bisa dipakai ulang | Pindah ke `Shared/Components` bila dipakai layar kedua |
