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
4. Perbarui dokumen QA dan Notion (bagian di bawah).

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

## Dokumen QA

- Satu dokumen per hari kerja di bawah "Changes Summary", judul `Saku <tgl> Okt: QA <topik>`.
- Isi: daftar langkah uji bernomor per fitur (aksi → hasil yang diharapkan), termasuk dark mode dan bahasa English bila relevan.
- Perbarui di dokumen yang sama setiap ada perubahan perilaku; jangan buat dokumen baru per revisi.
- Dokumen aktif: "Saku 7 Okt: QA ringkas", "Saku 8 Okt: QA Smart Tracker".

## Pitfall Swift 6 / SwiftUI yang sudah pernah kena

- Callback dari framework (speech, notifikasi) yang dibuat di dalam class `@MainActor` crash bila dipanggil di antrean lain: pakai fungsi `nonisolated static`.
- `UNUserNotificationCenterDelegate.didReceive`: pakai bentuk completion-handler, selesaikan di main.
- Overlay SwiftUI default-nya di tengah: beri `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)`.
- Jangan pakai `sed -i -E` di macOS; pakai `sed -i '' -E`.
- Crash log perangkat: `xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs --source / --destination <dir>`.

## Desain

HTML desain ada di `~/Downloads/sakuq-ui-revamp-styles*/project/*.dc.html`. Implementasikan terang dan gelap sekaligus; kalau ragu soal perilaku, tanya pemilik sebelum membangun.
