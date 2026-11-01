import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

/// Login hos Google og afsendelse af træninger til Google Health.
/// Træninger ligger i en kø i UserDefaults, til de er sendt, så de overlever manglende net og udløbet login.
@MainActor
@Observable
final class GoogleHealth {
    private static let clientID = "935284162719-60ihj7h4vsr7m5b9pf6mi75ho6nit278.apps.googleusercontent.com"
    private static let scheme = "com.googleusercontent.apps.935284162719-60ihj7h4vsr7m5b9pf6mi75ho6nit278"
    private static let redirect = scheme + ":/oauth2redirect"
    private static let scope = "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.writeonly"
    private static let endpoint = "https://health.googleapis.com/v4/users/me/dataTypes/exercise/dataPoints"
    private static let enabledKey = "gh_enabled"
    private static let queueKey = "gh_queue"
    private static let keychainAccount = "google_refresh_token"

    /// Forbindelsen er slået til. Forbliver sand, når login udløber, så træninger stadig kommer i kø.
    private(set) var enabled: Bool
    private(set) var needsLogin = false
    private(set) var queue: [GoogleWorkout] = []
    private(set) var busy = false
    private(set) var lastError: String?
    /// Antal træninger sendt, siden appen startede.
    private(set) var sentCount = 0
    /// Over 4 timer: venter på, at brugeren siger ja på slutskærmen.
    var longPending: GoogleWorkout?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessExpiry = Date.distantPast
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private var anchor: AuthAnchor?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if let d = UserDefaults.standard.data(forKey: Self.queueKey),
           let q = try? JSONDecoder().decode([GoogleWorkout].self, from: d) {
            queue = q
        }
    }

    // MARK: - kø

    /// Kaldes af finish().
    func workoutFinished(_ w: GoogleWorkout) {
        guard enabled else { return }
        if w.isLong {
            longPending = w
        } else {
            enqueue(w)
        }
    }

    func sendLongPending() {
        guard let w = longPending else { return }
        longPending = nil
        enqueue(w)
    }

    private func enqueue(_ w: GoogleWorkout) {
        if !queue.contains(where: { $0.id == w.id }) { queue.append(w) }
        saveQueue()
        flush()
    }

    private func saveQueue() {
        UserDefaults.standard.set(try? JSONEncoder().encode(queue), forKey: Self.queueKey)
    }

    /// Sender det, der ligger i køen.
    func flush() {
        guard enabled, !needsLogin, !busy, !queue.isEmpty else { return }
        busy = true
        Task {
            await sendAll()
            busy = false
            // En træning kan være kommet i køen, mens der blev sendt.
            if lastError == nil && !needsLogin && !queue.isEmpty { flush() }
        }
    }

    private func sendAll() async {
        for w in queue {
            do {
                try await send(w)
                queue.removeAll { $0.id == w.id }
                saveQueue()
                sentCount += 1
                lastError = nil
            } catch GHError.loginExpired {
                needsLogin = true
                lastError = nil
                return
            } catch {
                lastError = (error as? GHError)?.text ?? error.localizedDescription
                return
            }
        }
    }

    private func send(_ w: GoogleWorkout, retry: Bool = true) async throws {
        let token = try await validToken()
        guard let url = URL(string: Self.endpoint) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: w.body())
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code) { return }
        // Allerede sendt.
        if code == 409 { return }
        if code == 401 && retry {
            accessToken = nil
            try await send(w, retry: false)
            return
        }
        throw GHError.http(code, Self.errorMessage(data))
    }

    private static func errorMessage(_ data: Data) -> String {
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = o["error"] as? [String: Any],
           let m = e["message"] as? String {
            return m
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }

    // MARK: - login

    func connect() async {
        lastError = nil
        do {
            let verifier = Self.randomString()
            let state = Self.randomString()
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
            c?.queryItems = [
                URLQueryItem(name: "client_id", value: Self.clientID),
                URLQueryItem(name: "redirect_uri", value: Self.redirect),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: Self.scope),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state)
            ]
            guard let url = c?.url else { return }
            let callback = try await webAuth(url)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func item(_ n: String) -> String? { items.first { $0.name == n }?.value }
            if let e = item("error") { throw GHError.text("Google afviste login: " + e) }
            guard item("state") == state, let code = item("code") else {
                throw GHError.text("Login gav ikke et gyldigt svar.")
            }
            let o = try await tokenRequest([
                "client_id": Self.clientID,
                "code": code,
                "code_verifier": verifier,
                "grant_type": "authorization_code",
                "redirect_uri": Self.redirect
            ])
            let granted = (o["scope"] as? String) ?? ""
            if !granted.contains("activity_and_fitness.writeonly") {
                throw GHError.text("Du skal give MinApp lov til at tilføje træninger. Prøv igen, og sæt flueben ved tilladelsen.")
            }
            if let r = o["refresh_token"] as? String {
                Keychain.set(r, account: Self.keychainAccount)
            }
            storeAccess(o)
            enabled = true
            needsLogin = false
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            flush()
        } catch GHError.cancelled {
            return
        } catch {
            lastError = (error as? GHError)?.text ?? error.localizedDescription
        }
    }

    func disconnect() {
        Keychain.delete(account: Self.keychainAccount)
        accessToken = nil
        accessExpiry = .distantPast
        enabled = false
        needsLogin = false
        lastError = nil
        longPending = nil
        queue = []
        saveQueue()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    private func webAuth(_ url: URL) async throws -> URL {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow
        let provider = AuthAnchor(window: window ?? ASPresentationAnchor())
        anchor = provider
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.scheme) { callback, error in
                if let callback {
                    cont.resume(returning: callback)
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: GHError.cancelled)
                } else {
                    cont.resume(throwing: error ?? GHError.cancelled)
                }
            }
            s.presentationContextProvider = provider
            session = s
            s.start()
        }
    }

    private func validToken() async throws -> String {
        if let t = accessToken, accessExpiry > Date().addingTimeInterval(60) { return t }
        guard let refresh = Keychain.get(account: Self.keychainAccount) else { throw GHError.loginExpired }
        let o = try await tokenRequest([
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ])
        storeAccess(o)
        guard let t = accessToken else { throw GHError.text("Google gav ikke adgang.") }
        return t
    }

    private func storeAccess(_ o: [String: Any]) {
        accessToken = o["access_token"] as? String
        let sec = (o["expires_in"] as? NSNumber)?.doubleValue ?? 3000
        accessExpiry = Date().addingTimeInterval(sec)
    }

    private func tokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return [:] }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let form = params.map { k, v in
            k + "=" + (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)
        }.joined(separator: "&")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(form.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let o = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if (200..<300).contains(code) { return o }
        // Refresh-token udløbet eller tilbagekaldt.
        if (o["error"] as? String) == "invalid_grant" { throw GHError.loginExpired }
        let msg = (o["error_description"] as? String) ?? (o["error"] as? String) ?? "ukendt fejl"
        throw GHError.http(code, msg)
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum GHError: Error {
    case cancelled
    case loginExpired
    case text(String)
    case http(Int, String)

    var text: String {
        switch self {
        case .cancelled: return "Login blev afbrudt."
        case .loginExpired: return "Login er udløbet."
        case .text(let s): return s
        case .http(let c, let m): return "Google svarede \(c): \(m)"
        }
    }
}

private final class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: ASPresentationAnchor

    init(window: ASPresentationAnchor) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

private enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.louis.MinApp.google",
            kSecAttrAccount as String: account
        ]
    }

    static func set(_ value: String, account: String) {
        delete(account: account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Afsnittet på Program-fanen.
struct GoogleHealthSection: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let g = store.google
        Sec {
            SectionTitle(text: "Google Health")
            if !g.enabled {
                Text("Send dine egne træninger til Google Health som styrketræning, med navn, tidspunkt og varighed, når du afslutter. Appen får kun lov til at tilføje træninger, ikke læse dine data. Makkerens træninger sendes ikke.")
                    .smallMuted()
                Button("Forbind med Google") {
                    Task { await g.connect() }
                }
                .buttonStyle(BlockButtonStyle(outline: true, small: true))
            } else {
                Text(statusText(g))
                    .smallMuted()
                if g.needsLogin {
                    Button("Log ind igen") {
                        Task { await g.connect() }
                    }
                    .buttonStyle(BlockButtonStyle(outline: true, small: true))
                } else if !g.queue.isEmpty {
                    Button(g.busy ? "Sender…" : "Send nu") { g.flush() }
                        .buttonStyle(BlockButtonStyle(outline: true, small: true))
                        .disabled(g.busy)
                }
                Button("Afbryd forbindelsen") { g.disconnect() }
                    .buttonStyle(TextLinkStyle(color: T.red))
            }
            if let e = g.lastError {
                Text(e)
                    .font(.system(size: 13))
                    .foregroundStyle(T.red)
                    .textSelection(.enabled)
            }
        }
    }

    private func statusText(_ g: GoogleHealth) -> String {
        if g.needsLogin {
            return "Login er udløbet. Dine træninger venter (\(g.queue.count)) og sendes, når du logger ind igen."
        }
        if !g.queue.isEmpty {
            return "Forbundet. \(g.queue.count) træning(er) venter på at blive sendt."
        }
        if g.sentCount > 0 {
            return "Forbundet. \(g.sentCount) træning(er) sendt, siden appen blev åbnet."
        }
        return "Forbundet. Dine træninger sendes, når du afslutter."
    }
}
