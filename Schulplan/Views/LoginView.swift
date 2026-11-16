import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isLoggedIn {
                MainTabView()
                    .transition(.blurReplace)
            } else {
                LoginView()
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: model.isLoggedIn)
    }
}

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var accounts: [AccountChoice] = []
    @State private var chosenAccount: AccountChoice?
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 28) {
                    header
                    form
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 70)
                .padding(.bottom, 40)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: Binding(get: { !accounts.isEmpty }, set: { if !$0 { accounts = [] } })) {
            accountPicker
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 46, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 96, height: 96)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
            Text("Schulplan")
                .font(.largeTitle.bold())
            Text("Stundenplan, Vertretungen und Ausfälle aus Schulmanager Online – mit Mitteilung, sobald sich etwas ändert.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            field(icon: "person.fill") {
                TextField("E-Mail oder Benutzername", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            field(icon: "lock.fill") {
                SecureField("Passwort", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
            }
            if needsCode {
                field(icon: "number") {
                    TextField("Bestätigungscode", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .code)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                Text("Schulmanager hat einen Code per E-Mail oder Authenticator-App angefordert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button(action: submit) {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Anmelden").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || password.isEmpty || isWorking)
            .padding(.top, 4)
        }
        .animation(.smooth, value: needsCode)
        .animation(.smooth, value: error)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Button {
                Task { await model.startDemo() }
            } label: {
                Label("Ohne Konto ausprobieren", systemImage: "sparkles")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)

            Text("Inoffizielle App. Deine Zugangsdaten bleiben in der Keychain dieses Geräts und gehen nur an login.schulmanager-online.de.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .glassEffect(.regular, in: .capsule)
    }

    private var accountPicker: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    chosenAccount = account
                    accounts = []
                    submit()
                } label: {
                    Label(account.label.isEmpty ? "Konto" : account.label, systemImage: "person.crop.circle")
                }
            }
            .navigationTitle("Konto wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { accounts = [] }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty, !isWorking else { return }
        focus = nil
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                switch try await model.login(email: email, password: password, code: code, account: chosenAccount) {
                case .success: break
                case .twoFactor:
                    needsCode = true
                    focus = .code
                case .chooseAccount(let choices):
                    accounts = choices
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
