import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirm: String = ""
    @State private var isLoading = false

    var passwordsMatch: Bool { !password.isEmpty && password == confirm }

    var body: some View {
        VStack(spacing: 16) {
            Text("Create account")
                .font(.title).bold()

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !confirm.isEmpty && !passwordsMatch {
                Text("Passwords do not match.")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            if let msg = env.errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button {
                Task {
                    isLoading = true
                    defer { isLoading = false }
                    await env.register(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                       password: password)
                }
            } label: {
                HStack {
                    if isLoading { ProgressView() }
                    Text("Register")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || email.isEmpty || !passwordsMatch)

            Spacer()
        }
        .padding()
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
    }
}
