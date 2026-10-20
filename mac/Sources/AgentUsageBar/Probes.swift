import Foundation
import CryptoKit

struct Account: Codable, Identifiable, Hashable {
    var id: String
    var agent: String      // claude | codex | agy
    var label: String
    var dir: String?       // nil = the CLI's default login on this machine
}

struct Limit: Identifiable {
    let id = UUID()
    var label: String
    var percent: Double
    var resetsAt: Date?
    var note: String?
}

struct ModelRow: Identifiable {
    var id: String
    var name: String
    var detail: String?
    var blockedUntil: Date?
}

struct UsageResult: Identifiable {
    var account: Account
    var id: String { account.id }
    var plan: String?
    var email: String?
    var limits: [Limit] = []
    var models: [ModelRow] = []
    var notes: [String] = []
    var error: String?
    var limitReached = false
    var defaultModel: String?     // raw value from the CLI config (id, alias or display name)
    var defaultEffort: String?
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
let dataDir = home + "/.agent-usage"
let accFile = dataDir + "/accounts.json"

func loadAccounts() -> [Account] {
    guard let d = FileManager.default.contents(atPath: accFile) else { return [] }
    return (try? JSONDecoder().decode([Account].self, from: d)) ?? []
}
func saveAccounts(_ a: [Account]) {
    try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
    if let d = try? JSONEncoder().encode(a) { FileManager.default.createFiles(d) }
}
extension FileManager {
    func createFiles(_ d: Data) { createFile(atPath: accFile, contents: d, attributes: [.posixPermissions: 0o600]) }
}
func allAccounts() -> [Account] {
    [Account(id: "claude-default", agent: "claude", label: "Claude", dir: nil),
     Account(id: "codex-default", agent: "codex", label: "Codex", dir: nil),
     Account(id: "agy-default", agent: "agy", label: "Agy", dir: nil)] + loadAccounts()
}

// Login shell so PATH (node shims, ~/.local/bin) matches Terminal.
func sh(_ cmd: String, env: [String: String] = [:], timeout: TimeInterval = 20) async -> (ok: Bool, out: String) {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = Pipe()
            do { try p.run() } catch { cont.resume(returning: (false, "")); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            cont.resume(returning: (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? ""))
        }
    }
}

func getJSON(_ url: String, _ headers: [String: String]) async -> (status: Int, json: [String: Any]?) {
    guard let u = URL(string: url) else { return (0, nil) }
    var r = URLRequest(url: u, timeoutInterval: 15)
    headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
    guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (0, nil) }
    return ((resp as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: d) as? [String: Any])
}

func parseDate(_ s: String?) -> Date? {
    guard var s = s else { return nil }
    s = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: s)
}
func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

// MARK: Claude
func claudeCreds(_ a: Account) async -> [String: Any]? {
    var svc = "Claude Code-credentials"
    if let d = a.dir {
        let h = SHA256.hash(data: Data(d.utf8)).map { String(format: "%02x", $0) }.joined()
        svc += "-" + h.prefix(8)
    }
    let k = await sh("/usr/bin/security find-generic-password -s '\(svc)' -w")
    if k.ok, let j = try? JSONSerialization.jsonObject(with: Data(k.out.utf8)) as? [String: Any],
       let o = j["claudeAiOauth"] as? [String: Any] { return o }
    let f = (a.dir ?? home + "/.claude") + "/.credentials.json"
    if let d = FileManager.default.contents(atPath: f),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return j["claudeAiOauth"] as? [String: Any] }
    return nil
}

/// Access tokens last ~8h and only the Claude CLI refreshes them, so while it is idle the token expires and
/// the bar goes blank. Refresh here and write the rotated pair back to the keychain so the CLI stays logged in.
func refreshClaudeToken(_ a: Account, _ c: [String: Any]) async -> [String: Any]? {
    guard let rt = c["refreshToken"] as? String, a.dir == nil,
          let u = URL(string: "https://console.anthropic.com/v1/oauth/token") else { return nil }
    var req = URLRequest(url: u, timeoutInterval: 15)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token", "refresh_token": rt, "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"])
    guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let at = j["access_token"] as? String else { return nil }
    var n = c
    n["accessToken"] = at
    if let nr = j["refresh_token"] as? String { n["refreshToken"] = nr }
    if let ex = num(j["expires_in"]) { n["expiresAt"] = Int((Date().timeIntervalSince1970 + ex) * 1000) }
    guard let data = try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": n]), let s = String(data: data, encoding: .utf8) else { return nil }
    let w = await sh("/usr/bin/security add-generic-password -U -s 'Claude Code-credentials' -a \"$USER\" -w \(shq(s))")
    if !w.ok { return nil }   // rotated token not saved: keep the old pair rather than strand the CLI
    return n
}
func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func probeClaude(_ a: Account) async -> UsageResult {
    var r = UsageResult(account: a)
    guard var c = await claudeCreds(a), c["accessToken"] is String else {
        r.error = T("not_logged_claude"); return r
    }
    if let exp = num(c["expiresAt"]), exp / 1000 < Date().timeIntervalSince1970 + 120, let n = await refreshClaudeToken(a, c) { c = n }
    let tok = c["accessToken"] as! String
    r.plan = c["subscriptionType"] as? String
    let h = ["Authorization": "Bearer " + tok, "anthropic-beta": "oauth-2025-04-20", "anthropic-version": "2023-06-01", "User-Agent": "claude-code/2.1"]
    async let u = getJSON("https://api.anthropic.com/api/oauth/usage", h)
    async let m = getJSON("https://api.anthropic.com/v1/models?limit=100", h)
    async let pf = getJSON("https://api.anthropic.com/api/oauth/profile", h)
    let (U, M, P) = await (u, m, pf)
    // Profile is the source of truth for who is logged in; the keychain's subscriptionType can be stale.
    if let acct = P.json?["account"] as? [String: Any] { r.email = acct["email"] as? String }
    if let org = P.json?["organization"] as? [String: Any] {
        let tier = org["rate_limit_tier"] as? String ?? ""
        if let range = tier.range(of: #"max_\d+x"#, options: .regularExpression) { r.plan = "max " + tier[range].dropFirst(4) }
        else if let t = org["organization_type"] as? String { r.plan = t.replacingOccurrences(of: "claude_", with: "") }
    }
    if U.status == 401 { r.error = T("expired_claude"); return r }
    let names: [(String, String)] = [("five_hour", "Session (5h)"), ("seven_day", "Weekly – all models"), ("seven_day_opus", "Weekly – Opus"),
        ("seven_day_sonnet", "Weekly – Sonnet"), ("seven_day_oauth_apps", "Weekly – OAuth apps"), ("seven_day_cowork", "Weekly – Cowork")]
    let j = U.json ?? [:]
    for (k, label) in names {
        if let w = j[k] as? [String: Any], let p = num(w["utilization"]) { r.limits.append(Limit(label: label, percent: p, resetsAt: parseDate(w["resets_at"] as? String))) }
    }
    for (k, v) in j where !names.contains(where: { $0.0 == k }) {   // other windows (credits, promos…)
        if let w = v as? [String: Any], let p = num(w["utilization"]), w["resets_at"] is String {
            var note: String?
            if let lim = num(w["limit_dollars"]) { note = "$\(Int(num(w["used_dollars"]) ?? 0))/$\(Int(lim))" }
            r.limits.append(Limit(label: note != nil ? "Credits (USD)" : k.replacingOccurrences(of: "_", with: " "), percent: p, resetsAt: parseDate(w["resets_at"] as? String), note: note))
        }
    }
    if let ex = j["extra_usage"] as? [String: Any] { r.notes.append((ex["is_enabled"] as? Bool) == true ? T("extra_on") : T("extra_off")) }
    r.models = ((M.json?["data"] as? [[String: Any]]) ?? []).map {
        let ctx = (num($0["max_input_tokens"]).map { "\(Int($0 / 1000))k ctx" })
        return ModelRow(id: $0["id"] as? String ?? "?", name: $0["display_name"] as? String ?? "?", detail: ctx)
    }
    return r
}

// MARK: Codex
func probeCodex(_ a: Account) async -> UsageResult {
    var r = UsageResult(account: a)
    let dir = a.dir ?? home + "/.codex"
    guard let d = FileManager.default.contents(atPath: dir + "/auth.json"),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let t = j["tokens"] as? [String: Any], let tok = t["access_token"] as? String else {
        r.error = T("not_logged_codex"); return r
    }
    let h = ["Authorization": "Bearer " + tok, "chatgpt-account-id": t["account_id"] as? String ?? "", "User-Agent": "codex-cli"]
    async let u = getJSON("https://chatgpt.com/backend-api/wham/usage", h)
    async let m = sh("codex debug models", env: ["CODEX_HOME": dir])
    let (U, M) = await (u, m)
    if U.status == 401 || U.status == 403 { r.error = T("expired_codex"); return r }
    let x = U.json ?? [:]
    r.plan = x["plan_type"] as? String; r.email = x["email"] as? String
    func span(_ s: Double?) -> String { guard let s = s else { return "" }; return s >= 6 * 86400 ? "Weekly" : s >= 3600 ? "\(Int(s / 3600))h" : "\(Int(s / 60))m" }
    func win(_ label: String, _ w: Any?) {
        guard let w = w as? [String: Any], let p = num(w["used_percent"]) else { return }
        let l = label.replacingOccurrences(of: "{}", with: span(num(w["limit_window_seconds"])))
        r.limits.append(Limit(label: l, percent: p, resetsAt: num(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }))
    }
    let rl = x["rate_limit"] as? [String: Any] ?? [:]
    win("Primary ({})", rl["primary_window"]); win("Secondary ({})", rl["secondary_window"])
    r.limitReached = (rl["limit_reached"] as? Bool) == true
    let cr = x["code_review_rate_limit"] as? [String: Any] ?? [:]
    win("Code review ({})", cr["primary_window"]); win("Code review ({})", cr["secondary_window"])
    for e in (x["additional_rate_limits"] as? [[String: Any]]) ?? [] {
        let n = e["limit_name"] as? String ?? "extra"; let q = e["rate_limit"] as? [String: Any] ?? [:]
        win("\(n) ({})", q["primary_window"]); win("\(n) ({})", q["secondary_window"])
    }
    var blocked: [String: Date] = [:]
    for (k, v) in (x["model_usage"] as? [String: Any]) ?? [:] {
        if let v = v as? [String: Any], (v["available"] as? Bool) == false { blocked[k] = parseDate(v["available_at"] as? String) }
    }
    if let cr = x["credits"] as? [String: Any] { r.notes.append((cr["unlimited"] as? Bool) == true ? "Credits: unlimited" : "Credits: \(cr["balance"] ?? "0")") }
    if let rc = x["rate_limit_reset_credits"] as? [String: Any], let n = num(rc["available_count"]), n > 0 { r.notes.append("\(Int(n)) " + T("resets_left")) }
    if let mj = try? JSONSerialization.jsonObject(with: Data(M.out.utf8)) as? [String: Any] {
        r.models = ((mj["models"] as? [[String: Any]]) ?? []).map {
            let slug = $0["slug"] as? String ?? "?"
            return ModelRow(id: slug, name: $0["display_name"] as? String ?? slug, detail: slug, blockedUntil: blocked[slug])
        }
    }
    return r
}

// MARK: Agy
func probeAgy(_ a: Account) async -> UsageResult {
    var r = UsageResult(account: a)
    let m = await sh("agy models", env: a.dir.map { ["HOME": $0] } ?? [:])
    r.models = m.out.split(separator: "\n").compactMap {
        let p = $0.split(separator: "\t", maxSplits: 1).map(String.init)
        guard p.count == 2, p[0].range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil else { return nil }
        return ModelRow(id: p[0], name: p[1], detail: nil)
    }
    let tokPath = (a.dir ?? home) + "/.gemini/antigravity-cli/antigravity-oauth-token"
    if let d = FileManager.default.contents(atPath: tokPath), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
       let idt = j["id_token"] as? String, idt.split(separator: ".").count >= 2 {
        var b = String(idt.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        if let pd = Data(base64Encoded: b), let c = try? JSONSerialization.jsonObject(with: pd) as? [String: Any] { r.email = c["email"] as? String }
    }
    if r.models.isEmpty { r.error = T("not_logged_agy"); return r }
    // `agy -p "/usage"` prints "<group>\t<limit>\t<N>%\t<reset iso>" (N = remaining), no model call
    let u = await sh("agy -p /usage", env: a.dir.map { ["HOME": $0] } ?? [:], timeout: 30)
    for line in u.out.split(separator: "\n") {
        let c = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard c.count >= 3, c[2].hasSuffix("%"), let left = Double(c[2].dropLast()) else { continue }
        // "Gemini Models | Five Hour Limit Remaining" -> "Gemini · 5h"; "Gemini 4 Argon | Gemini 4 Argon Weekly Limit" -> "Argon · Weekly"
        let group = c[0].hasPrefix("Gemini 4") ? "Argon" : c[0].hasPrefix("Gemini") ? "Gemini" : "Claude/GPT"
        let label = "\(group) · " + (c[1].contains("Five Hour") ? "5h" : "Weekly")
        r.limits.append(Limit(label: label, percent: 100 - left, resetsAt: parseDate(c.count > 3 ? c[3] : nil)))
    }
    if r.limits.isEmpty { r.notes.append(T("agy_unreadable")) }
    return r
}

func probe(_ a: Account) async -> UsageResult {
    var r: UsageResult
    switch a.agent {
    case "claude": r = await probeClaude(a)
    case "codex": r = await probeCodex(a)
    default: r = await probeAgy(a)
    }
    (r.defaultModel, r.defaultEffort) = defaultModel(a)
    return r
}

// MARK: Default model (what the CLI uses when no --model is passed)
func configPath(_ a: Account) -> String {
    switch a.agent {
    case "claude": return (a.dir ?? home + "/.claude") + "/settings.json"
    case "codex": return (a.dir ?? home + "/.codex") + "/config.toml"
    default: return (a.dir ?? home) + "/.gemini/antigravity-cli/settings.json"
    }
}
// Line-level regexes so the user's formatting/ordering in their config files survives.
func configPattern(_ a: Account, _ key: String) -> String {
    a.agent == "codex" ? "(?m)^(\\s*\(key)\\s*=\\s*\")([^\"]*)(\")" : "(\"\(key)\"\\s*:\\s*\")([^\"]*)(\")"
}
func readConfigValue(_ a: Account, _ key: String) -> String? {
    guard let t = try? String(contentsOfFile: configPath(a), encoding: .utf8),
          let re = try? NSRegularExpression(pattern: configPattern(a, key)),
          let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let r = Range(m.range(at: 2), in: t) else { return nil }
    return String(t[r])
}
func writeConfigValue(_ a: Account, _ key: String, _ value: String) -> Bool {
    let path = configPath(a)
    guard let t = try? String(contentsOfFile: path, encoding: .utf8),
          let re = try? NSRegularExpression(pattern: configPattern(a, key)),
          re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil else { return false }
    let out = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t),
                                          withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: value) + "$3")
    return (try? out.write(toFile: path, atomically: true, encoding: .utf8)) != nil
}
func defaultModel(_ a: Account) -> (String?, String?) {
    switch a.agent {
    case "claude": return (readConfigValue(a, "model"), readConfigValue(a, "effortLevel"))
    case "codex": return (readConfigValue(a, "model"), readConfigValue(a, "model_reasoning_effort"))
    default: return (readConfigValue(a, "model"), nil)
    }
}
/// Switch the CLI's default model. Claude/Codex take the id, Agy stores the display name.
func setDefaultModel(_ a: Account, _ m: ModelRow) -> Bool {
    writeConfigValue(a, "model", a.agent == "agy" ? m.name : m.id)
}
func isCurrent(_ m: ModelRow, raw: String?) -> Bool {
    guard let raw = raw, !raw.isEmpty else { return false }
    return raw == m.id || raw == m.name || (raw.count > 2 && m.id.contains(raw) && !m.id.contains("["))
}
