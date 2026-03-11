import SwiftUI
import Foundation

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0; Scanner(string: s).scanHexInt64(&n)
        self.init(red: Double((n >> 16) & 0xFF)/255, green: Double((n >> 8) & 0xFF)/255, blue: Double(n & 0xFF)/255)
    }
}

// MARK: - Data Models

struct ClipboardEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let preview: String
    let byteSize: Int
    var isSensitive: Bool = false
}

struct DateGroup: Identifiable {
    let id = UUID()
    let label: String
    let entries: [ClipboardEntry]
}

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

enum ViewMode {
    case history
    case settings
}

// MARK: - Password Detector

enum PasswordDetector {
    private static let sensitivePhrases = [
        "password", "passwd", "pwd", "secret",
        "api_key", "apikey", "api-key", "api_secret",
        "token", "bearer", "private_key", "private-key",
        "credit_card", "creditcard", "cvv",
        "ssn", "social_security", "oauth",
        "client_secret", "database_url", "db_password"
    ]

    static func isLikelyPassword(_ text: String) -> Bool {
        let lower   = text.lowercased()
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if sensitivePhrases.contains(where: { lower.contains($0) }) { return true }
        if trimmed.hasPrefix("eyJ") || trimmed.hasPrefix("Bearer ") { return true }
        if trimmed.contains("-----BEGIN") && trimmed.contains("-----END") { return true }
        if lower.contains("email") && lower.contains("password") { return true }

        // Single-word, mixed-case, contains number → likely a password
        if trimmed.count > 12, !trimmed.contains(" ") {
            let u = trimmed.contains { $0.isUppercase }
            let l = trimmed.contains { $0.isLowercase }
            let n = trimmed.contains { $0.isNumber }
            if u && l && n { return true }
        }

        return false
    }
}

// MARK: - Storage Service

final class ClipboardStorage {
    static let shared = ClipboardStorage()
    private init() {}

    private var storagePath: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateCopyClip")
    }
    private var historyFile: URL { storagePath.appendingPathComponent("history.json") }

    func getStoragePath() -> String { historyFile.path }

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: storagePath, withIntermediateDirectories: true)
    }

    func load() -> [ClipboardEntry] {
        ensureDir()
        guard FileManager.default.fileExists(atPath: historyFile.path),
              let data = try? Data(contentsOf: historyFile),
              let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    func save(_ entries: [ClipboardEntry]) {
        ensureDir()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: historyFile)
    }
}

// MARK: - Clipboard Monitor (ViewModel)

final class ClipboardMonitor: NSObject, ObservableObject {
    @Published var entries:       [ClipboardEntry] = []
    @Published var groupedEntries:[DateGroup]       = []
    @Published var currentView:   ViewMode          = .history
    @Published var justCopiedID:  UUID?             = nil   // for flash feedback

    @AppStorage("historyLimit")           var historyLimit:           Int    = 100
    @AppStorage("passwordDetectionEnabled") var passwordDetectionEnabled: Bool = true
    @AppStorage("autoClearEnabled")       var autoClearEnabled:       Bool   = true
    @AppStorage("appTheme")               var appTheme:               String = AppTheme.system.rawValue
    @AppStorage("appPreset")              var appPreset:              String = "default"

    private var pollingTimer: Timer?
    private var writeTimer:   Timer?
    private var lastHash:     Int    = 0
    private var isDirty:      Bool   = false

    override init() {
        super.init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.startMonitoring()
        }
    }

    // MARK: Monitoring

    func startMonitoring() {
        entries = ClipboardStorage.shared.load()
        rebuildGroups()

        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }

        writeTimer?.invalidate()
        writeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.flushIfNeeded()
        }
    }

    private func poll() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let hash = text.hashValue
        guard hash != lastHash else { return }
        lastHash = hash
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if passwordDetectionEnabled && PasswordDetector.isLikelyPassword(text) { return }
        insert(text)
    }

    private func insert(_ text: String) {
        guard text.utf8.count <= 1_000_000 else { return }
        let entry = ClipboardEntry(
            id: UUID(),
            timestamp: Date(),
            text: text,
            preview: String(text.prefix(80)),
            byteSize: text.utf8.count
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.insert(entry, at: 0)
            self.entries = Array(self.entries.prefix(self.historyLimit))
            self.rebuildGroups()
            self.isDirty = true
            ClipboardStorage.shared.save(self.entries)   // immediate write for safety
        }
    }

    // MARK: Public Actions

    func copyToClipboard(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        lastHash = entry.text.hashValue          // don't re-add what we just pasted

        justCopiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.justCopiedID = nil
        }
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        rebuildGroups()
        isDirty = true
        ClipboardStorage.shared.save(entries)
    }

    func clearAll() {
        entries.removeAll()
        groupedEntries.removeAll()
        isDirty = false
        ClipboardStorage.shared.deleteAll()
    }

    // MARK: Grouping

    private func rebuildGroups() {
        let now = Date()
        var groups: [DateGroup] = []

        let tenMin  = entries.filter { diff(from: $0.timestamp, to: now, in: .minute)  <= 10 }
        let oneHour = entries.filter { diff(from: $0.timestamp, to: now, in: .minute)  <= 60 }
        let today   = entries.filter { diff(from: $0.timestamp, to: now, in: .hour)    <= 24 }
        let older   = entries.filter { diff(from: $0.timestamp, to: now, in: .hour)    >  24 }

        let hourOnly  = oneHour.filter { diff(from: $0.timestamp, to: now, in: .minute) > 10 }
        let todayOnly = today.filter   { diff(from: $0.timestamp, to: now, in: .hour)   >  1  }

        if !tenMin.isEmpty   { groups.append(DateGroup(label: "LAST 10 MINUTES", entries: tenMin)) }
        if !hourOnly.isEmpty  { groups.append(DateGroup(label: "LAST HOUR",       entries: hourOnly)) }
        if !todayOnly.isEmpty { groups.append(DateGroup(label: "TODAY",            entries: todayOnly)) }
        if !older.isEmpty     { groups.append(DateGroup(label: "OLDER",            entries: older)) }

        groupedEntries = groups
    }

    private func diff(from: Date, to: Date, in component: Calendar.Component) -> Int {
        Calendar.current.dateComponents([component], from: from, to: to).value(for: component) ?? 0
    }

    // MARK: Persistence

    private func flushIfNeeded() {
        guard isDirty else { return }
        if autoClearEnabled {
            let cutoff = Date(timeIntervalSinceNow: -30 * 86400)
            entries = entries.filter { $0.timestamp > cutoff }
            rebuildGroups()
        }
        ClipboardStorage.shared.save(entries)
        isDirty = false
    }

    deinit {
        pollingTimer?.invalidate()
        writeTimer?.invalidate()
        ClipboardStorage.shared.save(entries)
    }
}

// MARK: - Entry Row

struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let isCopied: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Copied flash indicator
            if isCopied {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(isCopied ? Color.accentColor : Color.primary)

                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Hover-only delete
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture { onTap() }
        .cursor(.pointingHand)
    }

    private var rowBackground: Color {
        if isCopied  { return Color.accentColor.opacity(0.12) }
        if isHovered { return Color.primary.opacity(0.06) }
        return Color.clear
    }
}

// MARK: - History View

struct ClipboardHistoryView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var searchText = ""

    private var displayGroups: [DateGroup] {
        guard !searchText.isEmpty else { return monitor.groupedEntries }
        return monitor.groupedEntries.compactMap { group in
            let hits = group.entries.filter {
                $0.text.localizedCaseInsensitiveContains(searchText)
            }
            return hits.isEmpty ? nil : DateGroup(label: group.label, entries: hits)
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Search bar ──────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Search clipboard history…", text: $searchText)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Entry list ──────────────────────────────────────────
            if monitor.entries.isEmpty {
                emptyState
            } else if displayGroups.isEmpty {
                noResultsState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(displayGroups) { group in
                            Section {
                                VStack(spacing: 4) {
                                    ForEach(group.entries) { entry in
                                        ClipboardEntryRow(
                                            entry:    entry,
                                            isCopied: monitor.justCopiedID == entry.id,
                                            onTap:    { monitor.copyToClipboard(id: entry.id) },
                                            onDelete: { monitor.delete(id: entry.id) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                            } header: {
                                HStack {
                                    Text(group.label)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(group.entries.count) item\(group.entries.count == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .background(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }

            Divider()

            // ── Bottom toolbar ──────────────────────────────────────
            HStack {
                // Count badge
                if !monitor.entries.isEmpty {
                    Text("\(monitor.entries.count) item\(monitor.entries.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Clear all
                if !monitor.entries.isEmpty {
                    Button {
                        let alert = NSAlert()
                        alert.messageText = "Clear all clipboard history?"
                        alert.informativeText = "This action cannot be undone."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Clear All")
                        alert.addButton(withTitle: "Cancel")
                        if alert.runModal() == .alertFirstButtonReturn {
                            monitor.clearAll()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all history")
                }

                // Settings
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        monitor.currentView = .settings
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 420, height: 500)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No clipboard history yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Start copying text — it will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No results for \"\(searchText)\"")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var updateStatus = ""
    @State private var isChecking   = false

    private func checkForUpdates() {
        isChecking = true; updateStatus = ""
        DispatchQueue.global().async {
            let path = "/Users/bogdantudorache/Desktop/Projects/PrivateCopyClip"
            let pull = Process()
            pull.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            pull.arguments = ["-C", path, "pull"]
            let pipe = Pipe(); pull.standardOutput = pipe
            try? pull.run(); pull.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if out.lowercased().contains("already up to date") {
                DispatchQueue.main.async { isChecking = false; updateStatus = "✓ Already up to date." }
            } else {
                DispatchQueue.main.async { updateStatus = "Update found — building…" }
                let build = Process()
                build.executableURL = URL(fileURLWithPath: "/bin/zsh")
                build.arguments = ["-c", "\(path)/build.sh"]
                try? build.run(); build.waitUntilExit()
                DispatchQueue.main.async {
                    isChecking = false
                    updateStatus = build.terminationStatus == 0 ? "✓ Updated! Relaunch to apply." : "✗ Build failed — check console."
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        monitor.currentView = .history
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.callout)
                        Text("Back")
                            .font(.callout)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                // Spacer mirror for balance
                Text("Back")
                    .font(.callout)
                    .opacity(0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // ── Settings body ───────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // History limit
                    settingSection("HISTORY") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Keep last")
                                .font(.callout)
                            Picker("Keep last", selection: $monitor.historyLimit) {
                                Text("10 items").tag(10)
                                Text("50 items").tag(50)
                                Text("100 items").tag(100)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    // Appearance
                    settingSection("APPEARANCE") {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Color scheme")
                                    .font(.callout)
                                Picker("Theme", selection: $monitor.appTheme) {
                                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                                        Text(theme.label).tag(theme.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Preset")
                                    .font(.callout)
                                Picker("Preset", selection: $monitor.appPreset) {
                                    Text("Default").tag("default")
                                    Text("Tokyo Night").tag("tokyoNight")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                if monitor.appPreset == "tokyoNight" {
                                    Text("Auto-switches background between #e6e7ed (light) and #24283b (dark)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Privacy
                    settingSection("PRIVACY") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Skip passwords & secrets", isOn: $monitor.passwordDetectionEnabled)
                                .font(.callout)

                            Toggle("Auto-clear entries older than 30 days", isOn: $monitor.autoClearEnabled)
                                .font(.callout)
                        }
                    }

                    // Updates
                    settingSection("UPDATES") {
                        VStack(alignment: .leading, spacing: 6) {
                            Button(isChecking ? "Checking…" : "Check for Updates") {
                                checkForUpdates()
                            }
                            .disabled(isChecking)
                            if !updateStatus.isEmpty {
                                Text(updateStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // About
                    settingSection("ABOUT") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("PrivateCopyClip v2.0.1")
                                    .font(.callout)
                                Spacer()
                                Link("Changelog ↗", destination: URL(string: "https://github.com/BogdanAlinTudorache/PrivateCopyClip/commits/main/")!)
                                    .font(.caption)
                            }
                            Text("All data is stored locally on your Mac. Nothing leaves your device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // ── Quit ─────────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Quit PrivateCopyClip") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 500)
    }

    @ViewBuilder
    private func settingSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Content View (router + theme)

struct ContentView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            switch monitor.currentView {
            case .history: ClipboardHistoryView(monitor: monitor)
            case .settings: SettingsView(monitor: monitor)
            }
        }
        .background(tokyoBackground)
        .onAppear { applyTheme() }
        .onChange(of: monitor.appTheme) { _ in applyTheme() }
    }

    private func applyTheme() {
        let t = AppTheme(rawValue: monitor.appTheme) ?? .system
        NSApp.appearance = t == .light ? NSAppearance(named: .aqua)
                         : t == .dark  ? NSAppearance(named: .darkAqua)
                         : nil
    }

    private var tokyoBackground: Color {
        guard monitor.appPreset == "tokyoNight" else { return .clear }
        return colorScheme == .dark ? Color(hex: "24283b") : Color(hex: "e6e7ed")
    }
}

// MARK: - Cursor helper

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - App Entry

@main
struct PrivateCopyClipApp: App {
    @StateObject private var monitor = ClipboardMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
                .symbolRenderingMode(.hierarchical)
            if monitor.entries.isEmpty {
                Text("0")
            } else {
                Text("\(monitor.entries.count)")
            }
        }
        .font(.system(.body))
    }
}
