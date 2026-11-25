# Sheet, dialog, halaman

## Sheet

Aturan keras: **semua sheet memakai `SmartSheet` atau `filterSheet`, dengan `SmartSheetFooter` untuk tombol.** Jangan membuat sheet sendiri, jangan menetapkan tinggi tetap; tinggi mengikuti isi.

| Pola | Komponen | Kapan |
|---|---|---|
| Sheet pilihan, form, daftar | `.filterSheet { footer }` (`FilterSheet.swift`) | Pilihan, isian, daftar pendek. Opsi: `showsMoreCue`, `detent`, `fullHeight`, `atLeastMedium` |
| Sheet keputusan dengan bingkai tetap | `SmartSheet(tone:icon:title:message:promises:)` | Persetujuan, konfirmasi, info. Lencana di samping judul, pesan, garis waktu janji, catatan. Nada: `consent` (hijau), `destructive` (merah), `neutral` (abu) |
| Konfirmasi singkat | `confirmDialog(...)` | Ya/tidak satu kalimat |

Isi sheet: judul 22 bold (`tracking(-0.3)`) rata kiri, subjudul 15 sekunder, isi dengan gutter 24, kotak di dalam sheet memakai `appSheetField`, footer `SmartSheetFooter`. Contoh acuan: sheet Undang anggota (`InviteViews.swift`), sheet tanggal gajian (`PaydayPicker.swift`).

Yang berhenti di sheet: pilihan dan tugas pendek. Tugas dengan beberapa langkah adalah halaman penuh (wizard), bukan sheet yang bertambah langkah.

## Dialog

`confirmDialog`: ikon bulat, judul, pesan satu kalimat, dua tombol. Tindakan merusak: `destructive: true` dan kata kerja spesifik ("Hapus", "Cabut kode"), bukan "Ya".

## Pola halaman

| Pola | Contoh | Aturan |
|---|---|---|
| Halaman daftar (tab) | Beranda, Transaksi, Profil | `ScreenHeader` 34, gutter 24, ruang bawah 96 |
| Halaman detail | Workspace, Kategori, Smart tracker | `detailPage`, judul navigasi tengah, kembali bulat kiri |
| Pengaturan berkelompok | Profil | Caption seksi 13 sekunder; kelompok: Workspace, Fitur, Tampilan, Akun; tanpa garis antar baris |
| Wizard bertahap | Tambah Workspace | Lihat bawah |
| Layar hasil | Sukses, gagal, batas gratis | Lihat bawah |

### Wizard bertahap

- Bilah atas: tombol kembali bulat (disembunyikan di langkah pertama), judul tengah 17 semibold, penghitung "n/N" 13.
- Progres: segmen tipis di bawah bilah atas, segmen aktif `appPrimary`.
- Kepala langkah: judul **30 bold** rata kiri, subjudul 15 sekunder. Langkah nama 28 dengan badge squircle di atasnya.
- Isi: gutter 24, jarak antar pilihan 12, pilihan tidak terpilih opasitas 0.55.
- Tombol bawah: `SmartSheetFooter` (1 : 3, kiri teks saja). Langkah pertama: kiri "Batal". Langkah terakhir: aksi hasil ("Tambah workspace").
- Validasi: galat muncul di bawah isian dengan goyang pendek dan haptik error; tombol tidak dikunci.
- Konfirmasi tak terbalikkan: tahan 1.2 dtk.

### Layar hasil

- **Sukses:** badge squircle 72-96 muncul dengan pegas, judul 26-28 bold, satu kalimat konfirmasi, aksi lanjutan (mis. kode undangan di tiket abu), satu tombol utama.
- **Gagal:** ikon bulat 88 berwarna `appError` 12%, judul 26 bold, satu paragraf, tombol "Coba lagi" (utama) dan "Tutup" (teks).
- **Batas gratis:** ikon mahkota, judul, penjelasan, "Lihat Plus" (utama) dan "Tidak sekarang" (teks).
- Pesan galat: apa yang terjadi, lalu apa yang bisa dilakukan; tidak pernah teks galat mentah.

## Status halaman

| Status | Pola |
|---|---|
| Memuat | `SkeletonBlock` berbentuk sama dengan hasil; tidak ada spinner layar penuh untuk pembaruan sebagian |
| Kosong | `EmptyMessage`: ikon, judul yang menamai ruang, satu kalimat, aksi kata kerja |
| Gagal | `ErrorStateView` atau `EmptyMessage` + "Coba lagi" |
| Hanya lihat (anggota non-Pemilik) | Kartu abu bergembok di atas daftar: "Kategori diatur Pemilik Workspace. Kamu bisa melihat dan memakainya."; baris di daftar menu tidak diberi subjudul |
