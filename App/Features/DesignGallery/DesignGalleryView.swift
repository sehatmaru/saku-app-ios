import SwiftUI

// TESTING ONLY: Profil > Menu uji > Galeri komponen. The real components, in the tokens of Docs/DesignSystem. Removed with Menu uji before release.

struct DesignGalleryView: View {
    @State private var showsSheet = false
    @State private var showsDialog = false
    @State private var picked = 0
    @State private var chip = true

    private let colors: [(String, Color)] = [
        ("appPrimary", .appPrimary), ("appPrimaryText", .appPrimaryText), ("appBrand", .appBrand), ("appSecondary", .appSecondary),
        ("appWarning", .appWarning), ("appError", .appError), ("appText", .appText), ("appBody", .appBody),
        ("appTextSecondary", .appTextSecondary), ("appTextTertiary", .appTextTertiary), ("appFill", .appFill), ("appSheetField", .appSheetField),
        ("appSeparator", .appSeparator), ("appDivider", .appDivider), ("appBorder", .appBorder), ("appInvestment", .appInvestment),
    ]
    private let sizes: [(CGFloat, Font.Weight, String)] = [
        (44, .bold, "Angka hero"), (34, .bold, "Judul layar"), (30, .bold, "Judul langkah"), (22, .bold, "Judul sheet"),
        (17, .semibold, "Tombol dan nilai"), (16, .regular, "Isi utama"), (15, .regular, "Isi"), (14, .regular, "Isi kecil"),
        (13, .regular, "Keterangan"), (12, .regular, "Keterangan kecil"), (11, .regular, "Label kecil"),
    ]
    private let radii: [(CGFloat, String)] = [(24, "24 notice"), (20, "20 kartu"), (16, "16 isian"), (14, "14 kolom"), (12, "12 kotak"), (10, "10 chip")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Warna") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        ForEach(colors, id: \.0) { name, color in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color).frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.appDivider))
                                Text(name).font(.app(10)).foregroundStyle(Color.appTextSecondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                section("Tipografi") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sizes, id: \.0) { size, weight, role in
                            HStack(alignment: .firstTextBaseline) {
                                Text("Saku").font(.app(size, weight: weight)).foregroundStyle(Color.appText)
                                Spacer()
                                Text(verbatim: "\(Int(size)) · \(role)").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                            }
                        }
                    }
                }
                section("Jarak dan radius") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach([4, 8, 12, 16, 24, 32, 40, 48], id: \.self) { value in
                                VStack(spacing: 4) {
                                    Rectangle().fill(Color.appPrimary).frame(width: CGFloat(value), height: CGFloat(value))
                                    Text(verbatim: "\(value)").font(.app(10)).foregroundStyle(Color.appTextSecondary)
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            ForEach(radii, id: \.0) { radius, label in
                                Text(label).font(.app(10)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity).frame(height: 52)
                                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                            }
                        }
                    }
                }
                section("Logo, avatar, badge") {
                    HStack(spacing: 16) {
                        SakuLogoIcon().frame(width: 48, height: 48)
                        InitialsAvatar(initials: "SS", size: 44, fontSize: 16)
                        WorkspaceBadge(icon: "house", color: nil, size: 44)
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.appPrimary).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "building.2").foregroundStyle(.white))
                    }
                }
                section("Tombol") {
                    VStack(spacing: 16) {
                        PrimaryButton(title: "Tombol utama") {}
                        SmartSheetFooter(primary: "Aksi utama", secondary: "Batal")
                        SmartSheetFooter(primary: "Hapus", destructive: true, secondary: "Batal")
                        SmartSheetFooter(primary: "Aksi tenang", ink: true, secondary: "Nanti")
                        SmartSheetFooter(primary: "Sedang menyimpan", isBusy: true, secondary: "Batal")
                    }
                }
                section("Pilihan dan isian") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            FilterChip(title: "Semua", isSelected: chip) { chip = true }
                            FilterChip(title: "Bulan ini", isSelected: !chip) { chip = false }
                        }
                        ForEach(0..<2, id: \.self) { index in
                            Button { picked = index } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: index == 0 ? "plus.circle" : "doc.on.doc").font(.system(size: 22)).foregroundStyle(Color.appTextSecondary).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: index == 0 ? "Kartu pilihan" : "Pilihan lain").font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                                        Text(verbatim: "Subjudul 14, jarak antar kartu 12.").font(.app(14)).foregroundStyle(Color.appTextSecondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: picked == index ? "checkmark.circle.fill" : "circle").foregroundStyle(picked == index ? Color.appPrimary : Color.appBorder)
                                }
                                .padding(16)
                                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .opacity(picked == index ? 1 : 0.55)
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
                section("Notice, kosong, pemuatan") {
                    VStack(spacing: 12) {
                        NoticeCard(icon: "exclamationmark", tone: .critical, title: "Nada kritis", message: "Merah, tint 9%.")
                        NoticeCard(icon: "bell", tone: .warning, title: "Nada peringatan", message: "Oranye.")
                        NoticeCard(icon: "checkmark", tone: .neutral, title: "Nada netral", message: "Hijau.")
                        EmptyMessage(icon: "tray", title: "Mulai dompet pertama", message: "Satu kalimat yang menjelaskan ruang ini.")
                        HStack(spacing: 10) { SkeletonBlock(width: 44, height: 44, radius: 22); SkeletonBlock(height: 14) }
                    }
                }
                section("Sheet, dialog, toast") {
                    VStack(spacing: 10) {
                        galleryButton("Buka sheet (filterSheet)") { showsSheet = true }
                        galleryButton("Buka dialog konfirmasi") { showsDialog = true }
                        galleryButton("Tampilkan toast") { ToastCenter.shared.show("Tersimpan") }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 96)
        }
        .background(Color.appBackground)
        .navigationTitle("Galeri komponen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSheet) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Judul sheet").font(.app(22, weight: .bold)).tracking(-0.3)
                Text("Sheet memakai filterSheet dan SmartSheetFooter. Tinggi mengikuti isi.").font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20)
            .filterSheet { SmartSheetFooter(primary: "Simpan", secondary: "Batal", onPrimary: { showsSheet = false }, onSecondary: { showsSheet = false }) }
        }
        .confirmDialog(isPresented: $showsDialog, icon: "trash", destructive: true, title: "Hapus contoh?",
                       message: "Dialog konfirmasi: judul, satu kalimat, dua tombol.", confirmTitle: "Hapus") { showsDialog = false }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            content()
        }
    }

    private func galleryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }
}
