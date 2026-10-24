import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var busy = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "box.truck.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Moove").font(.largeTitle.bold())
                Text("Scan your room. Agents sort, sell, buy and pack. You stay in charge.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = auth.error {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                busy = true
                Task {
                    await auth.signIn()
                    busy = false
                }
            } label: {
                Group {
                    if busy { ProgressView() } else { Text("Sign in") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || !auth.isConfigured)

            Button("Continue without an account") { auth.continueAsGuest() }
                .font(.subheadline)
            Text("Without an account, your data is tied to this device only.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

#Preview {
    LoginView().environment(AuthService())
}
