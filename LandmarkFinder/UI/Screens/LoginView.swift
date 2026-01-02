import SwiftUI
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var showPassword = false

    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValidEmail: Bool {
        // Simple but effective email check
        let pattern = #"^\S+@\S+\.\S+$"#
        return trimmedEmail.range(of: pattern, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        !isLoading && isValidEmail && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Landmark Finder")
                        .font(.largeTitle).bold()
                        .multilineTextAlignment(.center)
                    Text("Sign in to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    // Email
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Email")

                    if !email.isEmpty && !isValidEmail {
                        Text("Please enter a valid email address.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    // Password
                    ZStack {
                        if showPassword {
                            TextField("Password", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { tryLogin() }
                                .padding(.trailing, 44)
                                .padding(.leading, 16)
                                .frame(height: 44)
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { tryLogin() }
                                .padding(.trailing, 44)
                                .padding(.leading, 16)
                                .frame(height: 44)
                        }

                        HStack {
                            Spacer()
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.trailing, 12)
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                    }
                    .padding(.vertical, 2)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack {
                        Button {
                            // TODO: Wire to your reset flow when available
                            env.errorMessage = "Password reset not implemented."
                        } label: {
                            Text("Forgot password?")
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }

                if let msg = env.errorMessage {
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                Button {
                    tryLogin()
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.white) }
                        Text("Login")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.7)
                .accessibilityHint("Logs in with the provided email and password")

                // Google Sign-In Button
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "g.circle.fill")
                        Text("Continue with Google")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                NavigationLink("Create an account", destination: RegisterView())
                    .padding(.top, 6)

                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle("Login")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            dismissKeyboard()
        }
        .onChange(of: env.state) {
            // Clear error when auth state changes
            env.errorMessage = nil
        }
        .disabled(isLoading) // prevent edits while loading
        .animation(.easeInOut, value: isLoading)
        .animation(.easeInOut, value: env.errorMessage)
    }

    private func tryLogin() {
        guard canSubmit else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            await env.login(email: trimmedEmail, password: password)
        }
    }

    private func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let vc = UIApplication.shared.topMostViewController() else {
                env.errorMessage = "Unable to present Google Sign-In."
                return
            }
            try await env.googleLogin(presenting: vc)
        } catch {
            env.errorMessage = "Google Sign-In failed."
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Presenter helper
private extension UIApplication {
    func topMostViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        if let nav = root as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topMostViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return root
    }
}
