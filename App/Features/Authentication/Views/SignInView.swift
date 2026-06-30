import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

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
                    backgroundColor: .white,
                    foregroundColor: .appText,
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
                    backgroundColor: .black,
                    foregroundColor: .white,
                    hasBorder: false,
                    isLoading: authViewModel.isAppleLoading,
                    action: authViewModel.signInWithApple
                ) {
                    Image(systemName: "applelogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }

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
                    authViewModel.signInAsGuest()
                } label: {
                    Text("Lanjutkan sebagai Tamu")
                        .font(.jakarta(15, weight: .medium))
                        .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appPrimary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl + 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onAppear { authViewModel.errorMessage = nil }
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

#Preview {
    SignInView()
        .environmentObject(AuthViewModel())
}
