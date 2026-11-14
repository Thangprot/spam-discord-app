import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var tokenInput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Discord Spammer").font(.largeTitle).bold()
            TextField("Nhập User Token", text: $tokenInput).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
            if let err = app.loginError { Text(err).foregroundStyle(.red).font(.caption) }
            Button {
                app.token = tokenInput
                Task { await app.login() }
            } label: {
                if app.isLoading { ProgressView() } else { Text("Đăng nhập").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(tokenInput.isEmpty || app.isLoading)
        }.padding()
    }
}