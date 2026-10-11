# Saku (iOS) — alur kerja

SwiftUI iOS 18, Swift 6, xcodegen (`project.yml`), Supabase. Pemilik berbahasa Indonesia: balas dalam bahasa Indonesia.
Branch kerja: `feature-saku.2.0.0`.

## Setelah fitur atau fix selesai (lakukan tanpa menunggu diminta)

1. Test relevan lulus (`Tests/Unit`). Satu test lama PaydayCycle gagal di "Okt" vs "Oct"; abaikan.
2. Commit dan push. Satu commit per fitur, pesan `feat|fix(area): ...`.
3. Build dan pasang ke kedua perangkat:
   - Zahard `00008120-000404C91E2A601E`
   - Ruth Cinta Grace `00008120-00181DEC26C3601E`
   - `xcodebuild -scheme Saku -destination id=<UDID> -allowProvisioningUpdates DEVELOPMENT_TEAM=6474C8P8BL build`, lalu install dan launch dengan `xcrun devicectl`.
   - Simulator: iPhone 18 Pro `A3D21890-1936-4B1A-BAD2-780A81C837CF`.
   - Ruth kadang gagal launch (profil terkunci atau belum dipercaya, error 10002): laporkan, jangan diulang terus.
4. Perbarui dokumen QA dan Notion (bagian di bawah). Untuk epic yang sudah dimigrasi ke ClickUp, perbarui status dan assignee di ClickUp sesuai alurnya (bagian ClickUp).

## Lokalisasi

- Teks Indonesia adalah kunci. Pakai `Text("...")` atau `L("...")` / `Lx(id, en:)`. `Text(variabelString)` TIDAK diterjemahkan: bungkus `Text(L(x))`.
- Setiap teks baru: tambahkan terjemahan ke `Docs/en_part6.json` (cek dulu tidak duplikat di part lain), lalu `python3 Docs/build_catalog.py`.
- Xcode menulis ulang `Localizable.xcstrings` saat build. Cek jumlah kunci tetap sama (sekarang 1042 dan bertambah); bila rusak, jalankan lagi `build_catalog.py`.

## Supabase

- Migrasi di `Supabase/migrations/`. Pemilik menjalankannya sendiri; jangan `apply_migration`, cukup tulis file dan beri tahu.
- Edge Function `smart-parse` sudah ditulis tapi belum di-deploy: menunggu `ANTHROPIC_API_KEY` dari pemilik. Selama itu parser di perangkat yang dipakai.

## Notion

Tool: `mcp__...notion-*` (fetch, create-pages, update-page, update-data-source, query-data-sources). Tidak ada tool hapus: halaman lama dihapus manual oleh pemilik.

| Tempat | ID |
|---|---|
| Ticket Tracker (db) | `e11c0b50-0abb-4a94-ac56-009aa2a52df0`, data source `3f6d764f-6fb8-4774-a97f-79fc7c179107` |
| PRD Tracker (db) | `7f8f3ca7-0f47-4256-a883-654f2fa183c5`, data source `f1d7d372-41a1-42d5-b645-a218fb74b931` |
| Bug Tracker Saku (data source) | `0d27a65a-25fc-47e3-862e-c7b5b96aee8f` |
| Halaman "Changes Summary" | tempat dokumen QA |

- **Assignee:** status In review → Ruth (`user://ea180a2c-153e-41b8-a080-9f076182843a`); status lain → sehatmaru (`user://84d2af01-f33a-496c-a6f9-cf251cd66735`).
- **Ticket Tracker:** satu tiket per butir kebutuhan (BR/SM...), Phase/Platform/Priority diisi, relasi `PRD` ke baris PRD Tracker (dua arah dengan `Tickets`). Alur status: Backlog → In progress → In review → Done. Setelah build terpasang, set In review + Ruth. Jangan set Done sebelum pemilik memverifikasi.
- **PRD Tracker:** ubah status baris tracker (bukan halaman dokumen PRD) mengikuti tiketnya.
- **Bug Tracker:** properti Judul, Kategori, Priority (P0–P3), Status, Assignee, Pelapor, Platform, Tanggal lapor, ID `BUG-n`. Bug dari pemilik dicatat saat dilaporkan; setelah fix terpasang → In review + Ruth.

## ClickUp

Pencatatan fitur, user story, dan test case sedang dimigrasi dari Notion ke ClickUp. Untuk epic yang sudah ada di ClickUp, ClickUp adalah sumber utama; aturan Notion di atas berlaku untuk yang belum dimigrasi. Tool: `mcp__...clickup_*`.

| Tempat | ID |
|---|---|
| Workspace | `1100340000021799` |
| Space "Saku" | `1100340000085078` |
| List "Epic 3 - Dompet & Aset" (contoh/template) | `1100340000113305` |
| sehatmaru | `312863633` |
| Ruth Cinta | `119403650` |

**Hierarki:** Epic = List, lalu Fitur **atau** Enhancement = task, lalu User Story = subtask, lalu Test Case = subtask dari story.
- Judul: `Fitur N - ...`, `Enhancement N - ...` (perubahan pada fitur yang sudah ada), `User Story N - ...`, `TC N - ...`. Penomoran Fitur, Enhancement, dan TC per epic; User Story per Fitur/Enhancement. Contoh: Epic 6 - Kategori = Fitur 1, Fitur 2, Enhancement 1.
- Isi PRD (masalah, keputusan, scope, peta jalan) ada di deskripsi Fitur; tidak ada ClickUp Doc terpisah. Deskripsi User Story: "Sebagai user..." + acceptance criteria. Deskripsi TC: Skenario, Hasil yang diharapkan, Hasil pengujian.
- Epic: 1 Akun & Masuk, 2 Profil & Pengaturan, 3 Dompet & Aset, 4 Kartu Kredit & Tagihan, 5 Transaksi, 6 Kategori, 7 Budget, 8 Beranda & Insight, 9 Smart Tracker, 10 Fondasi Teknis, 11 Saku Plus (termasuk Referral). PRD yang belum dikembangkan masuk ke epic domainnya (Analisis Periode dan Ekspor ke Epic 8, Perampingan Kategori sebagai Enhancement di Epic 6).

**Status (6):** backlog (belum dikerjakan), in development (sedang dikerjakan), in review (sedang di-test), need fixing (butuh di-fix), need retest (butuh di-retest), done. Status hanya bisa diubah di pengaturan Space, tidak lewat tool.

**Assignee hanya di User Story dan Test Case** (Fitur, Enhancement, dan Epic kosong):
- Story backlog / in development: sehatmaru; test case kosong.
- Story in review: Ruth Cinta; semua test case-nya juga Ruth Cinta.
- Test case gagal: TC jadi need fixing dan assignee sehatmaru; story ikut need fixing dan sehatmaru.
- Setelah diperbaiki: story dan TC jadi need retest, assignee kembali Ruth Cinta.
- Hanya Ruth yang boleh set done (story dan TC). Jangan set done sendiri.
- Status Fitur mengikuti story di bawahnya; Epic tidak punya status.

**Batas API:** tool ClickUp dibatasi 100 panggilan per hari. Jangan boros: satu task per panggilan, hindari baca ulang. Untuk volume besar pakai impor CSV (bawah) atau minta pemilik upgrade paket.

**Impor CSV:** satu file per epic, `Epic-NN-Nama.csv`, diimpor ke list epic-nya (list baru dibuat dulu oleh pemilik bila belum ada). Kolom: `Task ID, Subtask IDs, Task Name, Description content, Task assignee, Status, Priority, Tags`. Hierarki dibentuk dari kolom `Subtask IDs` di baris induk (ID sumber seperti `F1`, `F1.US1`, `F1.US1.TC1`, dipisah koma); pemetaan kolom harus manual di layar impor. **Deskripsi di CSV harus teks polos** (tanpa tabel, `**`, atau poin berbintang) karena impor tidak membaca markdown; deskripsi lewat tool (`markdown_description`) boleh markdown. Impor ulang epic yang sudah diimpor menggandakan task: hapus dulu hasil impor lama.

## Dokumen QA

- Satu dokumen per hari kerja di bawah "Changes Summary", judul `Saku <tgl> Okt: QA <topik>`.
- Isi: daftar langkah uji bernomor per fitur (aksi → hasil yang diharapkan), termasuk dark mode dan bahasa English bila relevan.
- Perbarui di dokumen yang sama setiap ada perubahan perilaku; jangan buat dokumen baru per revisi.
- Dokumen aktif: "Saku 7 Okt: QA ringkas", "Saku 8 Okt: QA Smart Tracker", "Saku 9 Okt: QA Kartu kredit".

## Pitfall Swift 6 / SwiftUI yang sudah pernah kena

- Callback dari framework (speech, notifikasi) yang dibuat di dalam class `@MainActor` crash bila dipanggil di antrean lain: pakai fungsi `nonisolated static`.
- `UNUserNotificationCenterDelegate.didReceive`: pakai bentuk completion-handler, selesaikan di main.
- Overlay SwiftUI default-nya di tengah: beri `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)`.
- Jangan pakai `sed -i -E` di macOS; pakai `sed -i '' -E`.
- Crash log perangkat: `xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs --source / --destination <dir>`.

## Desain

HTML desain ada di `~/Downloads/sakuq-ui-revamp-styles*/project/*.dc.html`. Implementasikan terang dan gelap sekaligus; kalau ragu soal perilaku, tanya pemilik sebelum membangun.
