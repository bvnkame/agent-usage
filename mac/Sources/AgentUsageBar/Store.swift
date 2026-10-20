import SwiftUI
import AppKit

@MainActor
final class Store: ObservableObject {
    @Published var results: [UsageResult] = []
    @Published var updated: Date?
    @Published var loading = false
    @AppStorage("refreshSeconds") var refreshSeconds: Double = 60 { didSet { schedule() } }
    @AppStorage("showAgentInBar") var showAgent = "all"   // "all" or one agent: what the menu bar shows
    @AppStorage("lang") var lang = "vi" { didSet { objectWillChange.send(); Task { await refresh() } } }   // texts inside probe results are translated at probe time
    @AppStorage("showEmail") var showEmail = false   // emails hidden until toggled or clicked
    private var timer: Timer?

    init() { schedule(); Task { await refresh() } }

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(10, refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        let accs = allAccounts()
        let out = await withTaskGroup(of: (Int, UsageResult).self) { g -> [UsageResult] in
            for (i, a) in accs.enumerated() { g.addTask { (i, await probe(a)) } }
            var arr: [(Int, UsageResult)] = []
            for await x in g { arr.append(x) }
            return arr.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        results = out; updated = Date(); loading = false
    }

    static let barAgents = [("claude", NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)),
                            ("codex", NSColor(red: 0.06, green: 0.64, blue: 0.5, alpha: 1)),
                            ("agy", NSColor(red: 0.42, green: 0.55, blue: 1, alpha: 1))]

    /// Remaining % of the tightest limit of one window kind ("5h" session or "week") across an agent's accounts,
    /// nil when it has no usable reading. agy quota is per model group: only the default model's group counts.
    func remaining(_ agent: String, _ window: String) -> Double? {
        let rs = results.filter { $0.account.agent == agent && $0.error == nil }
        let limits = rs.flatMap { r -> [Limit] in
            guard agent == "agy", let m = r.defaultModel?.lowercased() else { return r.limits }
            let group = m.contains("gemini") ? "Gemini" : "Claude/GPT"
            return r.limits.filter { $0.label.hasPrefix(group + " ·") }
        }.filter { l in
            let t = l.label.lowercased()
            if t.contains("credits") || t.contains("code review") { return false }
            let isSession = t.contains("5h") || t.contains("five hour") || t.contains("session")
            return window == "5h" ? isSession : (t.contains("week") || t.contains("secondary")) && !isSession
        }
        guard let used = limits.map(\.percent).max() else { return nil }
        return max(0, 100 - used)
    }
    func barColor(_ r: Double?) -> NSColor {
        guard let r = r else { return .labelColor }
        return r <= 10 ? .systemRed : r <= 30 ? .systemOrange : .labelColor
    }
    /// Menu bar image: gauge icon, then per agent its logo and two small rows (5h quota above, weekly below).
    var barImage: NSImage {
        let agents = Store.barAgents.filter { ag in (showAgent == "all" || showAgent == ag.0) && results.contains(where: { r in r.account.agent == ag.0 }) }
        let rows = agents.map { (a: ($0.0, $0.1), h5: remaining($0.0, "5h"), wk: remaining($0.0, "week")) }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        let tag = NSFont.systemFont(ofSize: 7, weight: .medium)
        let text: (Double?) -> String = { $0.map { "\(Int($0.rounded()))%" } ?? "—" }
        let numW: CGFloat = 30, logoW: CGFloat = 14, gap: CGFloat = 8, h: CGFloat = 22
        let width = 20 + CGFloat(rows.count) * (logoW + 3 + numW + gap)
        return NSImage(size: NSSize(width: max(width, 40), height: h), flipped: false) { _ in
            if let g = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil) {
                let tinted = g.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
                tinted.isTemplate = true
                NSColor.labelColor.set()
                let r = NSRect(x: 0, y: (h - 14) / 2, width: 14, height: 14)
                tinted.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            }
            var x: CGFloat = 20
            for row in rows {
                drawLogo(row.a.0, color: row.a.1, in: NSRect(x: x, y: (h - logoW) / 2, width: logoW, height: logoW))
                x += logoW + 3
                for (i, v) in [row.h5, row.wk].enumerated() {
                    let y: CGFloat = i == 0 ? h / 2 : 0
                    NSAttributedString(string: i == 0 ? "5h" : "w", attributes: [.font: tag, .foregroundColor: NSColor.secondaryLabelColor])
                        .draw(at: NSPoint(x: x, y: y + 0.5))
                    NSAttributedString(string: text(v), attributes: [.font: font, .foregroundColor: self.barColor(v)])
                        .draw(at: NSPoint(x: x + 9, y: y))
                }
                x += numW + gap
            }
            return true
        }
    }

    func addAccount(agent: String, name: String) {
        let id = "\(agent)-\(String(UUID().uuidString.prefix(6)).lowercased())"
        let dir = dataDir + "/" + id
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let n = loadAccounts().filter { $0.agent == agent }.count + 1
        saveAccounts(loadAccounts() + [Account(id: id, agent: agent, label: name.isEmpty ? "\(agent) #\(n)" : name, dir: dir)])
        let cmd = ["claude": "CLAUDE_CONFIG_DIR='\(dir)' claude auth login", "codex": "CODEX_HOME='\(dir)' codex login", "agy": "HOME='\(dir)' agy"][agent]!
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        NSAppleScript(source: "tell application \"Terminal\" to do script \"\(esc)\"\ntell application \"Terminal\" to activate")?.executeAndReturnError(nil)
    }
    func switchModel(_ a: Account, _ m: ModelRow) {
        guard setDefaultModel(a, m) else { return }
        Task { await refresh() }
    }
    func remove(_ a: Account) { saveAccounts(loadAccounts().filter { $0.id != a.id }); Task { await refresh() } }
}

/// Simplified vector marks of each CLI's logo, drawn in the agent's colour.
func drawLogo(_ agent: String, color: NSColor, in r: NSRect) {
    color.setFill(); color.setStroke()
    let c = NSPoint(x: r.midX, y: r.midY), R = r.width / 2
    switch agent {
    case "claude":      // Claude spark: 12 tapered rays around a centre
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let len = R * (i % 2 == 0 ? 1.0 : 0.78)
            let p = NSBezierPath(); p.lineWidth = 1.7; p.lineCapStyle = .round
            p.move(to: NSPoint(x: c.x + cos(a) * R * 0.22, y: c.y + sin(a) * R * 0.22))
            p.line(to: NSPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len)); p.stroke()
        }
    case "codex":       // Codex: rounded cloud tile with ">_"
        let b = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 1.5), xRadius: R * 0.55, yRadius: R * 0.55); b.fill()
        NSColor.white.setStroke()
        let ch = NSBezierPath(); ch.lineWidth = 1.5; ch.lineCapStyle = .round; ch.lineJoinStyle = .round
        ch.move(to: NSPoint(x: r.minX + R * 0.55, y: c.y + R * 0.3)); ch.line(to: NSPoint(x: r.minX + R * 0.95, y: c.y))
        ch.line(to: NSPoint(x: r.minX + R * 0.55, y: c.y - R * 0.3)); ch.stroke()
        let u = NSBezierPath(); u.lineWidth = 1.5; u.lineCapStyle = .round
        u.move(to: NSPoint(x: c.x + R * 0.05, y: c.y - R * 0.32)); u.line(to: NSPoint(x: c.x + R * 0.5, y: c.y - R * 0.32)); u.stroke()
    default:            // Antigravity: the real logo bundled as agy.png
        if let url = Bundle.main.url(forResource: "agy", withExtension: "png"), let img = NSImage(contentsOf: url) {
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}
