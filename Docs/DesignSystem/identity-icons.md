# Identitas dan ikon

## Logo

| Aset | File | Pakai untuk |
|---|---|---|
| Tanda Saku (kantong) | `SakuLogoIcon.swift`, `Assets.xcassets/SakuMark.imageset` | Splash, login, kepala layar merek |
| Logo kantong beranimasi | `PocketLogo.swift` (`PocketShape`) | Splash dan layar pembuka |
| Wordmark | `Font.wordmark` (Plus Jakarta Sans ExtraBold) | Hanya tulisan "Saku" |
| Ikon app | `Assets.xcassets/AppIcon.appiconset` | Layar utama iOS |
| Hijau merek | `appBrand` / `BrandGreen.colorset` | Latar splash dan login |

Aturan: logo tidak diberi bayangan atau gradien; di atas `appBrand` logo putih. Jangan menaruh wordmark di dalam layar fitur.

## Ikon

- **Sistem ikon: SF Symbols** (outline). Jangan mencampur keluarga ikon lain di satu layar. Tidak ada emoji di tampilan.
- Ukuran umum: ikon baris 20, ikon kartu pilihan 21-26, ikon tombol 15-17, chevron 13 semibold.
- Warna: ikon sekunder `appTextSecondary`; ikon aktif/dipilih `appPrimary`; ikon destruktif `appError`; ikon di atas warna isian: putih.
- Ikon baris menu tidak boleh kembar antar baris (contoh: Workspace `building.2`, Ajak teman `person.2`).
- Chevron `chevron.right` (13, semibold, `appTextTertiary`) untuk baris yang membuka halaman.

## Avatar dan badge

| Komponen | File | Bentuk | Catatan |
|---|---|---|---|
| `InitialsAvatar` | `InitialsAvatar.swift` | Lingkaran | Foto profil, atau inisial putih di atas `appPrimary` (default 34) |
| `WalletIconView` / `WalletIconBadgeView` | `WalletIconView.swift`, `Models/WalletIcon.swift` | Lingkaran atau kotak | Logo bank dan e-wallet dari `Assets.xcassets` (bca, gopay, ovo, dan lainnya); dompet kustom: teks pendek di atas warna preset |
| `WalletSwatch` / `CategorySwatch` | `CategorySwatch.swift` | Kotak membulat | Warna kategori dan dompet |
| `WorkspaceBadge` | `Features/Workspace/Views/WorkspaceViews.swift` | Lingkaran (daftar), squircle (wizard) | Ikon atau foto di atas warna Workspace; Pribadi abu |

Badge Workspace di wizard memakai squircle (radius 29% sisi, `.continuous`): 76 untuk langkah nama, 84 langkah tampilan, 96 layar sukses. Daftar Workspace masih lingkaran; lihat `findings.md`.

## Warna kategori, dompet, Workspace

Palet preset ada di `WalletIcon.presetColors` dan `WorkspaceStyle.color(...)`. Satu keluarga abu (hangat atau dingin, tidak dicampur). Warna baru harus lolos kontras putih di atasnya.
