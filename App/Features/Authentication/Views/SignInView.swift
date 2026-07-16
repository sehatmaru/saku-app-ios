import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showGuestSheet = false
    @State private var guestName = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.lg) {
                Spacer()

                Image(systemName: "leaf.fill")
                    .font(.jakarta(80))
                    .foregroundColor(.white)

                HStack(spacing: Spacing.xs) {
                    Text("kelola")
                        .font(.jakarta(15, weight: .light))
                    Text("finansialmu")
                        .font(.jakarta(22, weight: .bold))
                    Text("dengan")
                        .font(.jakarta(15, weight: .light))
                    Text("SakuQ")
                        .font(.jakarta(22, weight: .bold))
                }
                .foregroundColor(.white)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.appPrimary.ignoresSafeArea(edges: .top))

            VStack(spacing: Spacing.md) {
                Spacer().frame(height: Spacing.xxl)

                socialButton(
                    label: "Lanjutkan dengan Google",
                    backgroundColor: googleButtonBg,
                    foregroundColor: googleButtonFg,
                    hasBorder: true,
                    isLoading: authViewModel.isGoogleLoading,
                    action: authViewModel.signInWithGoogle
                ) {
                    Image("GoogleLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }

                socialButton(
                    label: "Lanjutkan dengan Apple",
                    backgroundColor: appleButtonBg,
                    foregroundColor: appleButtonFg,
                    hasBorder: false,
                    isLoading: authViewModel.isAppleLoading,
                    action: {}
                ) {
                    Image(systemName: "applelogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .disabled(true)

                HStack(spacing: Spacing.sm) {
                    Color(.systemGray5)
                        .frame(height: 1)
                    Text("atau")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)
                    Color(.systemGray5)
                        .frame(height: 1)
                }

                Button {
                    showGuestSheet = true
                } label: {
                    Text("Lanjutkan sebagai Tamu")
                        .font(.jakarta(15, weight: .medium))
                        .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appPrimary.opacity(guestButtonOpacity))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(true)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl + 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onAppear { authViewModel.errorMessage = nil }
        .sheet(isPresented: $showGuestSheet) {
            guestSheet
        }
    }

    private var appleButtonBg: Color {
        colorScheme == .dark ? .white : .black
    }

    private var appleButtonFg: Color {
        colorScheme == .dark ? .black : .white
    }

    private var googleButtonBg: Color {
        .white
    }

    private var googleButtonFg: Color {
        colorScheme == .dark ? .black : .appText
    }

    private var guestButtonOpacity: Double {
        colorScheme == .dark ? 0.15 : 0.08
    }

    private var guestSheet: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.appPrimary)

                Text("Perkenalkan dirimu")
                    .font(.jakarta(22, weight: .bold))
                    .foregroundColor(.appText)

                Text("Masukkan namamu untuk memulai")
                    .font(.jakarta(14))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.top, Spacing.xxl)

            TextField("Nama kamu", text: $guestName)
                .textFieldStyle(.plain)
                .font(.jakarta(17))
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, Spacing.xl)

            PrimaryButton(
                title: "Simpan",
                isLoading: false,
                action: {
                    authViewModel.signInAsGuest(name: guestName)
                }
            )
            .padding(.horizontal, Spacing.xl)

            Spacer()
        }
        .interactiveDismissDisabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func socialButton(
        label: String,
        backgroundColor: Color,
        foregroundColor: Color,
        hasBorder: Bool,
        isLoading: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .frame(width: 20, height: 20)
                } else {
                    icon()
                        .frame(width: 20, height: 20)
                    Text(label)
                        .font(.jakarta(15, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.systemGray4), lineWidth: hasBorder ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
