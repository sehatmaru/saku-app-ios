# Konten dan bahasa

## Lokalisasi

- **Teks Indonesia adalah kunci.** `Text("...")`, `L("...")`, `Lx(id, en:)`.
- `Text(stringVariable)` TIDAK diterjemahkan: bungkus `Text(L(x))`.
- Setiap string baru: tambah terjemahan Inggris ke `Docs/en_part6.json` (cek tidak duplikat di part lain), lalu `python3 Docs/build_catalog.py`.
- Xcode menulis ulang `Localizable.xcstrings` saat build: hitung jumlah kunci sebelum dan sesudah; jika turun atau rusak, jalankan `build_catalog.py` lagi. Commit `Localizable.xcstrings` bersama string.

## Istilah baku

| Pakai | Bukan |
|---|---|
| Workspace (kapital W) | ruang kerja, space |
| Workspace Pribadi | akun pribadi |
| Pemilik, Anggota | Owner, Member (di teks Indonesia) |
| Kode undangan | kode ajakan |
| Awal periode / Tanggal gajian | cut-off |
| Dompet | akun (untuk wallet) |
| Smart tracker | pencatat pintar |
| Ajak teman | referral |

## Nada

- Menyapa pengguna dengan "kamu", kalimat pendek, kata kerja di depan.
- Tombol: kata kerja 1-3 kata ("Tambah workspace", "Salin kode"); satu niat satu label (jangan "Mulai", "Lanjut", "Berikutnya" bergantian untuk hal sama).
- Galat: apa yang terjadi + apa yang bisa dilakukan. Tanpa kata "berhasil", "mohon", seru "!".
- Tanpa em dash. Tanpa istilah korporat kosong (memberdayakan, mulus, canggih).
- Satu pesan cukup satu kali; jangan mengulang catatan yang sama di banyak baris.

## Format

- Uang: rupiah, pemisah titik ribuan; nominal pemasukan hijau, pengeluaran netral.
- Tanggal: ikuti locale perangkat; "Berlaku sampai 2 Desember 2026".
- Hitungan: "2 orang", "7 hari", "n/N".
- Kode undangan: huruf kapital dikelompokkan (`InviteCode.grouped`), font mono.

## Tampilan gelap, aksesibilitas

- Semua warna lewat token berpasangan; implementasi terang dan gelap bersamaan. Uji gelap hanya bila diminta, tapi kode selalu mendukungnya.
- Area ketuk minimal 44pt. Ikon tanpa teks diberi `accessibilityLabel`. Pilihan terpilih memakai `.isSelected`.
- Kontras teks 4.5:1 (teks hijau kecil memakai `appPrimaryText`).
- Dynamic Type: pakai ukuran dari tabel tipografi; lihat `findings.md` soal ukuran tetap.

## Yang dilarang

- Garis berlebihan sebagai hiasan, bayangan dekoratif, gradien.
- Emoji di tampilan, ikon dari keluarga lain.
- Sheet buatan sendiri, tinggi sheet tetap.
- Tombol kedua dengan latar abu di grup tombol; dua kapsul penuh bersebelahan.
- Hex lepas di tampilan, radius di luar skala.
