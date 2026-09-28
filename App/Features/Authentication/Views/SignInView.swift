import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isLogoOpen = false
    @State private var showsGuest = false
    @State private var logoTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if showsGuest {
                GuestOnboardingView {
                    withAnimation(.settle(0.5)) { showsGuest = false }
                }
                .transition(.move(edge: .trailing))
            } else {
                login
                    .transition(.move(edge: .leading))
            }
        }
    }

    private var login: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("SakuQ")
                    .font(.wordmark(22))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .padding(.leading, 24)
                Spacer(minLength: 16)
                PocketLogo(isOpen: isLogoOpen, stagger: 0.14, duration: 1)
                    .frame(maxWidth: 260, maxHeight: 260)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { playLogo() }
                    .padding(.bottom, 40)
            }

            sheet
        }
        .background(Color.appBrand.ignoresSafeArea())
        .onAppear {
            authViewModel.errorMessage = nil
            playLogo()
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Atur uang tanpa ribet.")
                    .font(.app(30, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.appText)
                Text("Masuk untuk menyimpan data dengan aman dan membukanya di perangkat lain.")
                    .font(.app(16))
                    .lineSpacing(2.4)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(.app(13))
                    .foregroundStyle(Color.appError)
                    .padding(.top, 10)
            }

            VStack(spacing: 10) {
                // Apple sign-in stays off until the Apple provider is configured.
                socialButton("Lanjutkan dengan Apple", isLoading: authViewModel.isAppleLoading,
                             foreground: Color.appBackground, background: Color.appText, bordered: false) {} icon: {
                    Image(systemName: "apple.logo").font(.system(size: 20))
                }
                .disabled(true)
                .opacity(0.5)

                socialButton("Lanjutkan dengan Google", isLoading: authViewModel.isGoogleLoading,
                             foreground: .appText, background: .clear, bordered: true,
                             action: authViewModel.signInWithGoogle) {
                    Image("GoogleLogo").resizable().scaledToFit().frame(width: 19, height: 19)
                }

                Button {
                    withAnimation(.settle(0.5)) { showsGuest = true }
                } label: {
                    HStack(spacing: 6) {
                        Text("Masuk sebagai tamu")
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                    }
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)

                (Text("Dengan melanjutkan, kamu menyetujui ")
                 + Text("Ketentuan Layanan").foregroundStyle(Color.appText)
                 + Text(" dan ")
                 + Text("Kebijakan Privasi").foregroundStyle(Color.appText)
                 + Text("."))
                    .font(.app(12))
                    .foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 4)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(Color.appBackground)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Cards drop back into the pocket, then rise again after 450 ms.
    private func playLogo() {
        logoTask?.cancel()
        isLogoOpen = false
        logoTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            isLogoOpen = true
        }
    }

    private func socialButton(
        _ label: String,
        isLoading: Bool,
        foreground: Color,
        background: Color,
        bordered: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    icon()
                    Text(label)
                }
            }
            .font(.app(17, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(background, in: Capsule())
            .overlay {
                if bordered { Capsule().stroke(Color.appBorder, lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
