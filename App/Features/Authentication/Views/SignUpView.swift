import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Spacer().frame(height: Spacing.xxl)

                VStack(spacing: Spacing.sm) {
                    Image(systemName: "leaf.fill")
                        .font(.jakarta(36))
                        .foregroundColor(.appPrimary)
                    Text("Buat Akun")
                        .font(.jakarta(22, weight: .bold))
                }

                Spacer().frame(height: Spacing.md)

                VStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Nama Lengkap")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                        TextField("Nama Anda", text: $fullName)
                            .appTextFieldStyle()
                            .autocapitalization(.words)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Email")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                        TextField("email@example.com", text: $email)
                            .appTextFieldStyle()
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Password")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                        SecureField("Minimal 6 karakter", text: $password)
                            .appTextFieldStyle()
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Konfirmasi Password")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                        SecureField("Ulangi password", text: $confirmPassword)
                            .appTextFieldStyle()
                    }

                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.jakarta(12))
                            .foregroundColor(.appError)
                    }

                    if let error = passwordError {
                        Text(error)
                            .font(.jakarta(12))
                            .foregroundColor(.appError)
                    }

                    PrimaryButton(
                        title: "Daftar",
                        isLoading: authViewModel.isLoading
                    ) {
                        guard password == confirmPassword else {
                            passwordError = "Password tidak cocok"
                            return
                        }
                        passwordError = nil
                        authViewModel.register(email: email, password: password, fullName: fullName)
                    }

                    Button {
                        dismiss()
                    } label: {
                            Text("Sudah punya akun? **Masuk**")
                                .font(.jakarta(15))
                            .foregroundColor(.appTextSecondary)
                    }
                }
                .padding(.horizontal, Spacing.xl)

                Spacer()
            }
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
    }
}
