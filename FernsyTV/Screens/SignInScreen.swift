import FernsyCore
import SwiftUI

/// Placeholder: the provider's server, username and password.
struct SignInScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 30) {
            Text("Fernsy").font(.largeTitle.bold())
            TextField("Server address", text: $server)
                .textContentType(.URL)
                .accessibilityIdentifier("signin.server")
            TextField("Username", text: $username)
                .textContentType(.username)
                .accessibilityIdentifier("signin.username")
            SecureField("Password", text: $password)
                .accessibilityIdentifier("signin.password")
            Button("Sign In") {
                Task { await model.signIn(XtreamCredentials(server: server, username: username, password: password)) }
            }
            .disabled(server.isEmpty || username.isEmpty || password.isEmpty)
            .accessibilityIdentifier("signin.submit")
            if case .failed(let message) = model.signIn {
                Text(message).foregroundStyle(.red).accessibilityIdentifier("signin.error")
            }
        }
        .frame(maxWidth: 900)
    }
}
