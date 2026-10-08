# Bagikan ke Saku (Share Extension)

Kodenya sudah ada (`ShareViewController.swift`, `Info.plist`, `ShareInbox` di `App/Shared/Utilities`), tapi
target-nya **belum** dimasukkan ke `project.yml` karena butuh App Group yang harus didaftarkan lewat akun
Apple Developer di Xcode (build lewat command line tidak punya akses akun, dan akan gagal tanpa profil baru).

Mengaktifkan:
1. Di Xcode, buka target Saku > Signing & Capabilities > + Capability > App Groups > `group.id.saku.app`.
2. Tambahkan ke `project.yml`:

```yaml
  # di bawah targets > Saku > settings > base
        CODE_SIGN_ENTITLEMENTS: App/Resources/Saku.entitlements
  # di bawah targets > Saku > dependencies
      - target: SakuShare
  # target baru
  SakuShare:
    type: app-extension
    platform: iOS
    sources:
      - Extensions/Share
      - path: App/Shared/Utilities/ShareInbox.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: id.saku.app.share
        INFOPLIST_FILE: Extensions/Share/Info.plist
        CODE_SIGN_ENTITLEMENTS: Extensions/Share/SakuShare.entitlements
        SKIP_INSTALL: YES
```
3. `xcodegen generate`, lalu build dengan akun yang sudah login di Xcode.
