import SwiftUI

func agentColor(_ agent: String) -> Color {
    switch agent { case "claude": return Color(red: 0.85, green: 0.47, blue: 0.34); case "codex": return Color(red: 0.06, green: 0.64, blue: 0.5); default: return Color(red: 0.42, green: 0.55, blue: 1) }
}
let popupSize = NSSize(width: 786, height: 470)
/// "jane@gmail.com" -> "j•••@gmail.com"
func maskEmail(_ e: String) -> String {
    guard let at = e.firstIndex(of: "@") else { return "••••••" }
    return String(e.first ?? "•") + "•••••" + e[at...]
}
func levelColor(_ p: Double) -> Color { p >= 90 ? .red : p >= 70 ? .orange : .green }
func left(_ d: Date?, _ now: Date) -> String {
    guard let d = d else { return "" }
    let s = Int(d.timeIntervalSince(now)); if s <= 0 { return T("reset_done") }
    let days = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
    return T("reset_in") + " " + (days > 0 ? "\(days)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m")
}

struct LimitRow: View {
    let l: Limit
    @EnvironmentObject var store: Store   // re-render on language change
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(l.label).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                    if let n = l.note { Text(n).font(.system(size: 9)).foregroundStyle(.secondary) }
                    Spacer(minLength: 2)
                    Text("\(T("left")) \(100 - Int(l.percent.rounded()))%").font(.system(size: 11, weight: .semibold).monospacedDigit()).lineLimit(1).fixedSize()
                }
                ProgressView(value: min(max(l.percent, 0), 100), total: 100).tint(levelColor(l.percent)).controlSize(.mini)
                Text(left(l.resetsAt, ctx.date)).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

struct AccountCard: View {
    let r: UsageResult
    @EnvironmentObject var store: Store
    @State private var showModels = false
    @State private var revealEmail = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(agentColor(r.account.agent)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.account.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let e = r.email {
                        let shown = store.showEmail || revealEmail
                        Text(shown ? e : maskEmail(e)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .contentShape(Rectangle()).onTapGesture { revealEmail.toggle() }.help(shown ? "" : T("tap_reveal"))
                    }
                }
                Spacer(minLength: 4)
                if let p = r.plan { Text(p.uppercased()).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(agentColor(r.account.agent).opacity(0.18), in: Capsule()).foregroundStyle(agentColor(r.account.agent)) }
                if r.account.dir != nil { Button { store.remove(r.account) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            if let m = r.defaultModel {
                HStack(spacing: 6) {
                    Text(T("in_use")).font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "cpu").font(.system(size: 9))
                        Text(r.models.first { isCurrent($0, raw: m) }?.name ?? m).lineLimit(1).truncationMode(.middle)
                        if let e = r.defaultEffort { Text("· \(e)").opacity(0.75) }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(agentColor(r.account.agent).opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(agentColor(r.account.agent).opacity(0.5)))
                    .foregroundStyle(agentColor(r.account.agent))
                }
            }
            if let e = r.error { Text(e).font(.caption).foregroundStyle(.red).padding(7).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 7)) }
            if r.limitReached { Text(T("limit_hit")).font(.caption.weight(.semibold)).foregroundStyle(.red) }
            ForEach(r.limits) { LimitRow(l: $0) }
            ForEach(r.notes, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if !r.models.isEmpty {
                DisclosureGroup(isExpanded: $showModels) {
                    VStack(spacing: 0) {
                        ForEach(r.models) { m in
                            let cur = isCurrent(m, raw: r.defaultModel)
                            HStack(alignment: .top) {
                                Image(systemName: cur ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                                    .foregroundStyle(cur ? agentColor(r.account.agent) : Color.secondary.opacity(0.5))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(m.name).font(.system(size: 11.5)).lineLimit(1)
                                    Text(m.id).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if let b = m.blockedUntil { Text("\(T("blocked_until")) \(b.formatted(date: .omitted, time: .shortened))").font(.system(size: 9.5)).foregroundStyle(.red) }
                                else if let d = m.detail, d != m.id { Text(d).font(.system(size: 9.5)).foregroundStyle(.secondary) }
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                            .onTapGesture { if !cur { store.switchModel(r.account, m) } }
                            .help(cur ? T("in_use") : T("set_default"))
                            Divider().opacity(0.4)
                        }
                    }
                } label: { Text("\(T("models")) (\(r.models.count)) · \(T("models_hint"))").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
        }
        .padding(9)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var newAgent = "claude"
    @State private var newName = ""
    var presets: [(String, Double)] { [10, 30, 60, 120, 300, 900, 1800].map { ($0 < 60 ? "\(Int($0)) \(T("sec"))" : "\(Int($0 / 60)) \(T("min"))", $0) } }
    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            content()
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(T("language")) {
                Picker("", selection: $store.lang) { ForEach(Lang.allCases) { Text($0.name).tag($0.rawValue) } }.pickerStyle(.segmented).labelsHidden()
            }
            section(T("refresh_every")) {
                HStack {
                    Picker("", selection: Binding(get: { store.refreshSeconds }, set: { store.refreshSeconds = $0 })) {
                        ForEach(presets, id: \.1) { Text($0.0).tag($0.1) }
                        if !presets.contains(where: { $0.1 == store.refreshSeconds }) { Text("\(Int(store.refreshSeconds)) \(T("sec"))").tag(store.refreshSeconds) }
                    }.labelsHidden().frame(width: 120)
                    Stepper("", value: Binding(get: { store.refreshSeconds }, set: { store.refreshSeconds = max(10, $0) }), in: 10...3600, step: 10).labelsHidden()
                }
            }
            section(T("menubar_show")) {
                Picker("", selection: $store.showAgent) { Text(T("all3")).tag("all"); Text("Claude").tag("claude"); Text("Codex").tag("codex"); Text("Agy").tag("agy") }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
            }
            section(T("accounts")) {
                Toggle(T("show_email"), isOn: $store.showEmail).toggleStyle(.switch).controlSize(.small).font(.caption)
                ForEach(store.results) { r in
                    HStack(spacing: 6) {
                        Circle().fill(agentColor(r.account.agent)).frame(width: 8, height: 8)
                        Text(r.account.label).font(.system(size: 12, weight: .semibold))
                        Text(r.email.map { store.showEmail ? $0 : maskEmail($0) } ?? (r.account.dir == nil ? T("default_acc") : "")).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if r.account.dir != nil { Button(T("remove")) { store.remove(r.account) }.buttonStyle(.plain).font(.caption).foregroundStyle(.red) }
                    }
                }
                if adding {
                    HStack {
                        Picker("", selection: $newAgent) { Text("Claude").tag("claude"); Text("Codex").tag("codex"); Text("Agy").tag("agy") }.labelsHidden().frame(width: 100)
                        TextField(T("name_hint"), text: $newName).textFieldStyle(.roundedBorder)
                        Button(T("login")) { store.addAccount(agent: newAgent, name: newName); newName = ""; adding = false }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    Text(T("login_hint")).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Button { adding = true } label: { Label(T("add_account"), systemImage: "plus") }.buttonStyle(.plain).font(.caption.weight(.semibold))
                }
            }
            Spacer()
            Link(destination: URL(string: "https://buymeacoffee.com/bvnkame")!) { Label(T("coffee"), systemImage: "cup.and.saucer.fill") }
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
    }
}

/// "v1.0.0 (build 12) · by bvnkame", from the app bundle's Info.plist
var aboutLine: String {
    let i = Bundle.main.infoDictionary
    let v = i?["CFBundleShortVersionString"] as? String ?? "dev", b = i?["CFBundleVersion"] as? String ?? "0"
    return "v\(v) (build \(b)) · \(T("by")) bvnkame"
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(showSettings ? T("settings") : "Agent Usage").font(.system(size: 15, weight: .bold))
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                if let u = store.updated { Text(u.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
                Button { showSettings.toggle() } label: { Image(systemName: showSettings ? "chevron.backward" : "gearshape") }.buttonStyle(.plain).help(showSettings ? T("back") : T("settings"))
            }
            if showSettings { SettingsView() } else {
            if store.results.isEmpty { ProgressView().padding(40).frame(maxWidth: .infinity) }
            HStack(alignment: .top, spacing: 12) {
                ForEach([("claude", "Claude"), ("codex", "Codex"), ("agy", "Agy")], id: \.0) { agent, title in
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(agentColor(agent)).frame(width: 8, height: 8)
                            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 8) { ForEach(store.results.filter { $0.account.agent == agent }) { AccountCard(r: $0) } }
                        }
                    }.frame(width: 240)
                }
            }
            }
            HStack { Text(aboutLine).font(.caption2).foregroundStyle(.secondary); Spacer(); Button(T("quit")) { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
