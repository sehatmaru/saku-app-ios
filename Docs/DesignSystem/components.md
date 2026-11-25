# Komponen

Semua di `App/Shared/Components/` kecuali dicatat. Kolom "Kapan" adalah aturan pakai.

## Tombol

| Komponen | File | Bentuk | Kapan |
|---|---|---|---|
| `PrimaryButton` | `PrimaryButton.swift` | Kapsul hijau, tinggi 52, label 17 semibold; abu saat nonaktif | Satu aksi utama penuh lebar di layar (bukan sheet) |
| **`SmartSheetFooter`** | `SmartSheet.swift` | **Grup tombol standar** (lihat bawah) | Semua sheet dan semua layar dengan dua pilihan |
| `EmptyStateButton` | `QuietUI.swift` | Kapsul, `isSecondary` untuk abu | Aksi di status kosong dan gagal |
| `NoticeButton` | `NoticeCard.swift` | Kapsul kecil | Aksi di dalam notice |
| Tombol bulat | (lokal) | Lingkaran 40, `appFill` | Kembali, tutup |
| Tombol teks | (lokal) | Teks 15 semibold `appPrimary` atau `appTextSecondary` | Aksi tersier ("Lihat semua ikon", "Muat ulang kode") |

### Grup tombol standar (keputusan pemilik)

`SmartSheetFooter(primary:, secondary:)`:
- Satu baris, rasio **1 : 3** (kiri : kanan), jarak 12, tinggi 50 (`RatioRow`).
- **Kiri = batal atau tombol kedua: teks saja, tanpa latar** (16 medium, `appTextSecondary`).
- **Kanan = aksi utama: kapsul berisi** (17 semibold, putih di atas `appPrimary`).
- Variasi aksi utama: `destructive` (merah), `ink` (hitam di terang, putih di gelap, untuk aksi tenang), `dimmed` (tampak mati tapi tetap bisa diketuk untuk menunjukkan apa yang kurang), `isBusy` (spinner).
- Tanpa `secondary`: satu kapsul penuh. Tanpa `primary`: satu tombol teks penuh.
- Tidak ada grup tombol dengan latar abu di kiri, dan tidak ada dua kapsul berisi bersebelahan.
- Satu aksi utama per layar. Aksi tersier berupa teks.

## Isian dan pilihan

| Komponen | File | Catatan |
|---|---|---|
| Kolom isian | (lokal di wizard, `appFill`, radius 14, tinggi 54) | Fokus: garis `appPrimary` 1.5; galat: `appError` plus pesan 13 di bawah |
| `appTextFieldStyle()` | `Core/DesignSystem/TextFieldStyle.swift` | Lama (abu sistem, radius 12): jangan dipakai di layar baru |
| `FilterChip` | `FilterChip.swift` | Chip filter |
| `SegmentBar`, `SegmentTrack` | `QuietUI.swift`, `PocketLogo.swift` | Pilihan beberapa segmen; segmen progres |
| `TypePill` | `Features/Categories/Views/CategoriesView.swift` | Pil Pengeluaran / Pemasukan |
| `AmountKeyboard` | `AmountKeyboard.swift` | Papan angka nominal |
| `PaydayDayPicker`, `PaydaySheet` | `PaydayPicker.swift` | Pilih tanggal gajian (kisi 7 kolom) |
| Kartu pilihan | (lokal di wizard: `choiceCard`) | Ikon, judul 16-18, subjudul 14, bulatan centang; tidak dipilih opasitas 0.55 |

## Baris dan kartu

| Komponen | File | Catatan |
|---|---|---|
| `row(icon:title:subtitle:)` | `Features/Profile/Views/ProfileView.swift` | Baris menu: ikon 20, judul 16, nilai di kanan 15 sekunder, chevron |
| `TransactionRowView` | `TransactionRowView.swift` | Baris transaksi |
| `NoticeCard` | `NoticeCard.swift` | Kartu notice Beranda: lencana bulat, judul, pesan, maksimal dua aksi, tutup. Radius 24, tanpa garis dan bayangan, nada = tint 9% (`critical` merah, `warning` oranye, `neutral` hijau) |
| `SectionHeader` | `QuietUI.swift` | Judul seksi |
| `SectionDivider`, `rowSeparator()` | `QuietUI.swift` | Pemisah; pakai hemat |
| Kartu isian | (pola) | `appFill`, radius 16-20, tanpa garis tepi |

## Umpan balik

| Komponen | File | Catatan |
|---|---|---|
| `ToastCenter.shared.show(_, icon:, undo:)` | `ToastCenter.swift` | 1.9 dtk, 3.8 dtk bila ada "Urungkan"; pegas `duration 0.48 bounce 0.35` |
| `confirmDialog(...)` | `ConfirmDialog.swift` | Konfirmasi ikon + judul + pesan + tombol; `destructive`, `inkButton` |
| `ErrorStateView`, `ErrorBanner` | `ErrorStateView.swift` | Galat layar penuh dan banner |
| `EmptyMessage` | `QuietUI.swift` | Status kosong: ikon, judul, pesan |
| `SkeletonBlock`, `ShimmerModifier` | `QuietUI.swift`, `ShimmerModifier.swift` | Pemuatan dengan bentuk yang sama dengan hasil |
| `SwipeToConfirm` | `SwipeToConfirm.swift` | Geser untuk konfirmasi |
| Tahan untuk konfirmasi | (lokal wizard) | 1.2 dtk, `rigid` haptik; lepas lebih awal mengosongkan |

## Data

`HeroAmount`, `FlowSplitBar`, `CountingText`, `OdometerText` (angka bergerak) di `QuietUI.swift`. Angka memakai digit lebar tetap.

## Navigasi dan kerangka

| Komponen | File | Catatan |
|---|---|---|
| `AppTabBar` | `AppTabBar.swift` | Tab bawah; tab adalah setara, tidak bergeser |
| `detailPage(addLabel:onAdd:)` | `AppTabBar.swift` | Halaman detail dengan tombol tambah mengambang |
| `ScreenHeader` | `QuietUI.swift` | Judul besar 34, kembali hijau opsional |
| Tombol ✦ Smart Tracker | (di shell) | Mengambang; beri ruang 96 di bawah daftar |
| `ToastHost` / `toastHost()` | `ToastCenter.swift` | Pasang sekali di akar |

## Aturan membuat komponen baru

1. Cari dulu di daftar ini dan di `App/Shared/Components/`.
2. Dipakai di dua layar atau lebih: komponen bersama; satu layar: lokal, tetap ikuti token.
3. Tambahkan ke dokumen ini dan galeri DEBUG di perubahan yang sama.
