import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    Spacer().frame(height: Spacing.xxxl)

                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "leaf.fill")
                            .font(.jakarta(40))
                            .foregroundColor(.appPrimary)
                        Text("SakuQ")
                            .font(.jakarta(28, weight: .bold))
                            .foregroundColor(.appPrimary)
                    }

                    Spacer().frame(height: Spacing.lg)

                    VStack(spacing: Spacing.lg) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Email")
                                .font(.jakarta(12))
                                .foregroundColor(.appTextSecondary)
                            TextField("demo@sakuq.app", text: $email)
                                .appTextFieldStyle()
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Password")
                                .font(.jakarta(12))
                                .foregroundColor(.appTextSecondary)
                            SecureField("••••••••", text: $password)
                                .appTextFieldStyle()
                        }

                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.jakarta(12))
                                .foregroundColor(.appError)
                        }

                        PrimaryButton(
                            title: "Masuk",
                            isLoading: authViewModel.isLoading
                        ) {
                            authViewModel.login(email: email, password: password)
                        }

                        Button {
                            showSignUp = true
                        } label: {
                            Text("Belum punya akun? **Daftar**")
                                .font(.jakarta(15))
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    .padding(.horizontal, Spacing.xl)

                    Spacer()
                }
            }
            .background(Color.appBackground)
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }
}
