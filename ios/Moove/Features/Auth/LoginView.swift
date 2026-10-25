import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            MooveWordmark(height: 64)
                .padding(.bottom, 36)
            Text("Your move, handled.")
                .pageTitle()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let error = auth.error {
                Text(error)
                    .monoText(12.5)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
            }
            Button {
                busy = true
                Task {
                    await auth.signIn()
                    busy = false
                }
            } label: {
                Group {
                    if busy { ProgressView().tint(Theme.accentInk) } else { Text("Sign in") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .disabled(busy || !auth.isConfigured)

            Button { auth.continueAsGuest() } label: {
                Text("Continue without an account").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.outline))
            .padding(.top, 10)
            .accessibilityIdentifier("login.guest")
            .accessibilityHint("Your data stays on this device only")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 24)
        .mooveScreen()
    }
}

#Preview {
    LoginView().environment(AuthService())
}
