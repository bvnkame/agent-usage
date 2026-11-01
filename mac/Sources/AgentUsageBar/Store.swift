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
        // A transient failure (network, expired token) keeps the last good reading instead of blanking the bar.
        results = out.map { n in n.error != nil ? (results.first { $0.account.id == n.account.id && $0.error == nil } ?? n) : n }
        updated = Date(); loading = false
    }

    static let barAgents = [("claude", NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)),
                            ("codex", NSColor(red: 0.06, green: 0.64, blue: 0.5, alpha: 1)),
                            ("agy", NSColor(red: 0.42, green: 0.55, blue: 1, alpha: 1))]

    /// Remaining % of the tightest limit of one window kind ("5h" session or "week") across an agent's accounts,
    /// nil when it has no usable reading. agy quota is per model group; every group counts so the bar shows the tightest.
    func remaining(_ agent: String, _ window: String, group: String? = nil) -> Double? {
        let rs = results.filter { $0.account.agent == agent && $0.error == nil }
        let limits = rs.flatMap(\.limits).filter { l in
            if let g = group, !l.label.hasPrefix(g + " ·") { return false }
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
        // agy quota is per model group: one small column per group (G emini, C laude/GPT, A rgon); others get one column
        let agyGroups = [("G", "Gemini"), ("C", "Claude/GPT"), ("A", "Argon")]
        let rows = agents.map { ag -> (a: (String, NSColor), cols: [(tag: String, h5: Double?, wk: Double?)]) in
            let cols: [(tag: String, h5: Double?, wk: Double?)] = ag.0 == "agy"
                ? agyGroups.map { (tag: $0.0, h5: remaining("agy", "5h", group: $0.1), wk: remaining("agy", "week", group: $0.1)) }
                    .filter { $0.h5 != nil || $0.wk != nil }
                : [(tag: "", h5: remaining(ag.0, "5h"), wk: remaining(ag.0, "week"))]
            return (a: (ag.0, ag.1), cols: cols.isEmpty ? [(tag: "", h5: nil, wk: nil)] : cols)
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .semibold)
        let tag = NSFont.systemFont(ofSize: 5, weight: .medium)
        let text: (Double?) -> String = { $0.map { "\(Int($0.rounded()))%" } ?? "—" }
        let numW: CGFloat = 23, logoW: CGFloat = 10, gap: CGFloat = 4, tagW: CGFloat = 6.5, letW: CGFloat = 4, h: CGFloat = 22
        let width = 13 + rows.reduce(CGFloat(0)) { acc, row in
            acc + logoW + 2 + (row.cols.count > 1 ? tagW + CGFloat(row.cols.count) * (numW - tagW + letW) : numW) + gap }
        return NSImage(size: NSSize(width: max(width, 40), height: h), flipped: false) { _ in
            if let g = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil) {
                let tinted = g.withSymbolConfiguration(.init(pointSize: 9, weight: .regular))!
                tinted.isTemplate = true
                NSColor.labelColor.set()
                let r = NSRect(x: 0, y: (h - 10) / 2, width: 10, height: 10)
                tinted.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            }
            var x: CGFloat = 13
            for row in rows {
                drawLogo(row.a.0, color: row.a.1, in: NSRect(x: x, y: (h - logoW) / 2, width: logoW, height: logoW))
                x += logoW + 2
                let grouped = row.cols.count > 1
                if grouped {   // 5h / w tags once, then one number column per group with its letter between the rows
                    for (i, t) in ["5h", "w"].enumerated() {
                        NSAttributedString(string: t, attributes: [.font: tag, .foregroundColor: NSColor.secondaryLabelColor])
                            .draw(at: NSPoint(x: x, y: (i == 0 ? h / 2 : 0) + 0.5))
                    }
                    x += tagW
                }
                for c in row.cols {
                    if grouped {
                        NSAttributedString(string: c.tag, attributes: [.font: tag, .foregroundColor: NSColor.tertiaryLabelColor])
                            .draw(at: NSPoint(x: x, y: h / 2 - 4))
                        x += letW
                    }
                    for (i, v) in [c.h5, c.wk].enumerated() {
                        let y: CGFloat = i == 0 ? h / 2 : 0
                        if !grouped {
                            NSAttributedString(string: i == 0 ? "5h" : "w", attributes: [.font: tag, .foregroundColor: NSColor.secondaryLabelColor])
                                .draw(at: NSPoint(x: x, y: y + 0.5))
                        }
                        NSAttributedString(string: text(v), attributes: [.font: font, .foregroundColor: self.barColor(v)])
                            .draw(at: NSPoint(x: x + (grouped ? 0 : tagW), y: y))
                    }
                    x += grouped ? numW - tagW : numW
                }
                x += gap
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
