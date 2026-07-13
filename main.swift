import SwiftUI
import Foundation
import ServiceManagement

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0; Scanner(string: s).scanHexInt64(&n)
        self.init(red: Double((n >> 16) & 0xFF)/255, green: Double((n >> 8) & 0xFF)/255, blue: Double(n & 0xFF)/255)
    }
}

// MARK: - Tokyo Night Palette

struct TokyoPalette {
    let bg: Color
    let bgHighlight: Color
    let fg: Color
    let fgDark: Color
    let comment: Color
    let accent: Color
    let border: Color
    let searchBg: Color

    static let dark = TokyoPalette(
        bg:          Color(hex: "1a1b26"),
        bgHighlight: Color(hex: "1f2335"),
        fg:          Color(hex: "e0e4f7"),
        fgDark:      Color(hex: "8890b0"),
        comment:     Color(hex: "8890b0"),
        accent:      Color(hex: "7aa2f7"),
        border:      Color(hex: "292e42"),
        searchBg:    Color(hex: "1a1b26")
    )

    static let light = TokyoPalette(
        bg:          Color(hex: "d5d6db"),
        bgHighlight: Color(hex: "c4c5ca"),
        fg:          Color(hex: "1a1e36"),
        fgDark:      Color(hex: "4a5280"),
        comment:     Color(hex: "505366"),
        accent:      Color(hex: "2e4a82"),
        border:      Color(hex: "b4b5b9"),
        searchBg:    Color(hex: "d5d6db")
    )
}

private struct TokyoPaletteKey: EnvironmentKey {
    static let defaultValue: TokyoPalette? = nil
}

extension EnvironmentValues {
    var tokyoPalette: TokyoPalette? {
        get { self[TokyoPaletteKey.self] }
        set { self[TokyoPaletteKey.self] = newValue }
    }
}

// MARK: - Data Models

struct ClipboardEntry: Codable, Identifiable {
    let id: UUID
    var timestamp: Date
    let text: String?
    let preview: String
    let byteSize: Int
    var isSensitive: Bool = false
    var isPinned: Bool = false
    var contentType: ContentType = .text
    var imageFileName: String? = nil
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

enum ContentType: String, Codable {
    case text
    case image
}

enum ViewMode {
    case history
    case settings
}

enum AppLayout {
    static let width:  CGFloat = 460
    static let height: CGFloat = 580
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
    private var imagesDir: URL { storagePath.appendingPathComponent("images") }

    func getStoragePath() -> String { historyFile.path }

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: storagePath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
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

    func saveImage(id: UUID, pngData: Data) {
        ensureDir()
        let file = imagesDir.appendingPathComponent("\(id.uuidString).png")
        try? pngData.write(to: file, options: .atomic)
    }

    func loadImage(fileName: String) -> NSImage? {
        let file = imagesDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return NSImage(data: data)
    }

    func deleteImage(fileName: String) {
        let file = imagesDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: file)
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: historyFile)
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }
}

// MARK: - Clipboard Monitor (ViewModel)

final class ClipboardMonitor: NSObject, ObservableObject {
    @Published var entries:       [ClipboardEntry] = []
    @Published var groupedEntries:[DateGroup]       = []
    @Published var currentView:   ViewMode          = .history
    @Published var justCopiedID:  UUID?             = nil

    @AppStorage("historyLimit")             var historyLimit:             Int    = 100
    @AppStorage("passwordDetectionEnabled") var passwordDetectionEnabled: Bool   = true
    @AppStorage("autoClearEnabled")         var autoClearEnabled:         Bool   = true
    @AppStorage("appTheme")                 var appTheme:                 String = AppTheme.system.rawValue
    @AppStorage("appPreset")                var appPreset:                String = "default"

    private var pollingTimer:    Timer?
    private var writeTimer:      Timer?
    private var lastChangeCount: Int  = 0
    private var isDirty:         Bool = false

    override init() {
        super.init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.startMonitoring()
        }
    }

    // MARK: Monitoring

    func startMonitoring() {
        entries = ClipboardStorage.shared.load()
        lastChangeCount = NSPasteboard.general.changeCount
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
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        let pb = NSPasteboard.general

        let hasText  = pb.string(forType: .string) != nil
        let hasImage = pb.data(forType: .tiff) != nil || pb.data(forType: .png) != nil

        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sensitive = passwordDetectionEnabled && PasswordDetector.isLikelyPassword(text)
            insertText(text, isSensitive: sensitive)
        }

        if hasImage, let imgData = imageDataFromPasteboard(pb) {
            insertImage(imgData)
        }
    }

    private func imageDataFromPasteboard(_ pb: NSPasteboard) -> Data? {
        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let png = rep.representation(using: .png, properties: [:]) {
            guard png.count <= 10_000_000 else { return nil }
            return png
        }
        if let pngData = pb.data(forType: .png) {
            guard pngData.count <= 10_000_000 else { return nil }
            return pngData
        }
        return nil
    }

    // MARK: Insert (with duplicate detection)

    private func insertText(_ text: String, isSensitive: Bool = false) {
        guard text.utf8.count <= 1_000_000 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let idx = self.entries.firstIndex(where: { $0.contentType == .text && $0.text == text }) {
                var existing = self.entries.remove(at: idx)
                existing.timestamp = Date()
                if !existing.isPinned {
                    self.entries.insert(existing, at: 0)
                } else {
                    self.entries.insert(existing, at: 0)
                }
            } else {
                var entry = ClipboardEntry(
                    id: UUID(), timestamp: Date(), text: text,
                    preview: String(text.prefix(80)), byteSize: text.utf8.count,
                    contentType: .text
                )
                entry.isSensitive = isSensitive
                self.entries.insert(entry, at: 0)
            }

            self.enforceLimit()
            self.rebuildGroups()
            self.isDirty = true
            ClipboardStorage.shared.save(self.entries)
        }
    }

    private func insertImage(_ pngData: Data) {
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let img = NSImage(data: pngData)
        let w = Int(img?.size.width ?? 0)
        let h = Int(img?.size.height ?? 0)
        let sizeKB = pngData.count / 1024
        let preview = "Image \(w)x\(h) — \(sizeKB)KB"

        ClipboardStorage.shared.saveImage(id: id, pngData: pngData)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let entry = ClipboardEntry(
                id: id, timestamp: Date(), text: nil,
                preview: preview, byteSize: pngData.count,
                contentType: .image, imageFileName: fileName
            )
            self.entries.insert(entry, at: 0)
            self.enforceLimit()
            self.rebuildGroups()
            self.isDirty = true
            ClipboardStorage.shared.save(self.entries)
        }
    }

    private func enforceLimit() {
        let pinned   = entries.filter { $0.isPinned }
        let unpinned = entries.filter { !$0.isPinned }
        let kept     = Array(unpinned.prefix(historyLimit))
        let evicted  = Array(unpinned.dropFirst(historyLimit))
        for e in evicted {
            if let f = e.imageFileName { ClipboardStorage.shared.deleteImage(fileName: f) }
        }
        entries = pinned + kept
        entries.sort { $0.timestamp > $1.timestamp }
    }

    // MARK: Public Actions

    func copyToClipboard(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }

        NSPasteboard.general.clearContents()

        if entry.contentType == .image, let fileName = entry.imageFileName,
           let img = ClipboardStorage.shared.loadImage(fileName: fileName),
           let tiff = img.tiffRepresentation {
            NSPasteboard.general.setData(tiff, forType: .tiff)
        } else if let text = entry.text {
            NSPasteboard.general.setString(text, forType: .string)
        }

        lastChangeCount = NSPasteboard.general.changeCount

        justCopiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.justCopiedID = nil
        }
    }

    func delete(id: UUID) {
        if let entry = entries.first(where: { $0.id == id }),
           let f = entry.imageFileName {
            ClipboardStorage.shared.deleteImage(fileName: f)
        }
        entries.removeAll { $0.id == id }
        rebuildGroups()
        isDirty = true
        ClipboardStorage.shared.save(entries)
    }

    func togglePin(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isPinned.toggle()
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

        let pinned = entries.filter { $0.isPinned }
        let unpinned = entries.filter { !$0.isPinned }

        if !pinned.isEmpty { groups.append(DateGroup(label: "PINNED", entries: pinned)) }

        let tenMin    = unpinned.filter { now.timeIntervalSince($0.timestamp) <= 600 }
        let hourOnly  = unpinned.filter { let t = now.timeIntervalSince($0.timestamp); return t > 600 && t <= 3600 }
        let todayOnly = unpinned.filter { let t = now.timeIntervalSince($0.timestamp); return t > 3600 && t <= 86400 }
        let older     = unpinned.filter { now.timeIntervalSince($0.timestamp) > 86400 }

        if !tenMin.isEmpty    { groups.append(DateGroup(label: "LAST 10 MINUTES", entries: tenMin)) }
        if !hourOnly.isEmpty  { groups.append(DateGroup(label: "LAST HOUR",       entries: hourOnly)) }
        if !todayOnly.isEmpty { groups.append(DateGroup(label: "TODAY",            entries: todayOnly)) }
        if !older.isEmpty     { groups.append(DateGroup(label: "OLDER",            entries: older)) }

        groupedEntries = groups
    }

    // MARK: Persistence

    private func flushIfNeeded() {
        guard isDirty else { return }
        if autoClearEnabled {
            let cutoff = Date(timeIntervalSinceNow: -30 * 86400)
            let before = entries.count
            entries = entries.filter { $0.isPinned || $0.timestamp > cutoff }
            if entries.count != before { rebuildGroups() }
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
    let hideSecrets: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false
    @State private var isRevealed = false
    @Environment(\.tokyoPalette) private var tokyo

    private var timeString: String {
        let f = DateFormatter()
        let age = Date().timeIntervalSince(entry.timestamp)
        f.dateFormat = age > 86400 ? "MMM d, HH:mm" : "HH:mm:ss"
        return f.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isCopied {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .frame(width: 14)
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundColor(tokyo?.accent ?? Color.orange)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                if entry.contentType == .image {
                    imageContent
                } else if entry.isSensitive && hideSecrets && !isRevealed {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Sensitive content hidden")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(tokyo?.comment ?? Color.secondary)
                            .italic()
                    }
                } else {
                    let textColor = isCopied ? (tokyo?.accent ?? Color.accentColor) : (tokyo?.fg ?? Color.primary)
                    Text(entry.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .foregroundColor(textColor)
                }

                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(tokyo?.comment ?? Color.secondary)
            }

            Spacer()

            // Hover-only actions
            Button(action: onTogglePin) {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                    .font(.caption)
                    .foregroundColor(entry.isPinned ? (tokyo?.accent ?? Color.orange) : Color.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .help(entry.isPinned ? "Unpin" : "Pin")

            if entry.isSensitive && hideSecrets {
                Button { isRevealed.toggle() } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
                .help(isRevealed ? "Hide" : "Reveal")
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
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

    @ViewBuilder
    private var imageContent: some View {
        if let fileName = entry.imageFileName,
           let img = ClipboardStorage.shared.loadImage(fileName: fileName) {
            HStack(spacing: 8) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(tokyo?.border ?? Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                Text(entry.preview)
                    .font(.caption)
                    .foregroundColor(tokyo?.comment ?? Color.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                Text(entry.preview)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(tokyo?.fg ?? Color.primary)
            }
        }
    }

    private var rowBackground: Color {
        if let t = tokyo {
            if isCopied  { return t.accent.opacity(0.12) }
            if isHovered { return t.bgHighlight.opacity(0.6) }
            return Color.clear
        }
        if isCopied  { return Color.accentColor.opacity(0.10) }
        if isHovered { return Color.primary.opacity(0.05) }
        return Color.clear
    }
}

// MARK: - History View

struct ClipboardHistoryView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var searchText = ""
    @Environment(\.tokyoPalette) private var tokyo

    private var displayGroups: [DateGroup] {
        guard !searchText.isEmpty else { return monitor.groupedEntries }
        return monitor.groupedEntries.compactMap { group in
            let hits = group.entries.filter {
                ($0.text ?? $0.preview).localizedCaseInsensitiveContains(searchText)
            }
            return hits.isEmpty ? nil : DateGroup(label: group.label, entries: hits)
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Search bar ──────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(tokyo?.comment ?? Color.secondary)
                    .font(.callout)
                TextField("Search clipboard history…", text: $searchText)
                    .font(.callout)
                    .foregroundColor(tokyo?.fg ?? Color.primary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(tokyo?.comment ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(tokyo?.searchBg ?? Color(nsColor: .controlBackgroundColor))

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
                                        entryRow(for: entry)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                            } header: {
                                HStack {
                                    Text(group.label)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(tokyo?.accent ?? Color.secondary)
                                    Spacer()
                                    Text(itemCountLabel(group.entries.count))
                                        .font(.caption2)
                                        .foregroundColor(tokyo?.comment ?? Color.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .background(tokyo?.bg ?? Color(nsColor: .windowBackgroundColor))
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
                    Text(itemCountLabel(monitor.entries.count))
                        .font(.caption2)
                        .foregroundColor(tokyo?.comment ?? Color.secondary)
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
                            .foregroundColor(tokyo?.comment ?? Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all history")
                }

                // Settings
                Image(systemName: "gearshape")
                    .foregroundColor(tokyo?.comment ?? Color.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { monitor.currentView = .settings }
                    .cursor(.pointingHand)
                    .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: AppLayout.width, height: AppLayout.height)
    }

    private func itemCountLabel(_ count: Int) -> String {
        "\(count) item\(count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func entryRow(for entry: ClipboardEntry) -> some View {
        ClipboardEntryRow(
            entry:       entry,
            isCopied:    monitor.justCopiedID == entry.id,
            hideSecrets: monitor.passwordDetectionEnabled,
            onTap:       { monitor.copyToClipboard(id: entry.id) },
            onDelete:    { monitor.delete(id: entry.id) },
            onTogglePin: { monitor.togglePin(id: entry.id) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 36))
                .foregroundColor((tokyo?.comment ?? Color.secondary).opacity(0.4))
            Text("No clipboard history yet")
                .font(.callout)
                .foregroundColor(tokyo?.comment ?? Color.secondary)
            Text("Start copying text — it will appear here")
                .font(.caption)
                .foregroundColor((tokyo?.comment ?? Color.secondary).opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor((tokyo?.comment ?? Color.secondary).opacity(0.4))
            Text("No results for \"\(searchText)\"")
                .font(.callout)
                .foregroundColor(tokyo?.comment ?? Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var updateStatus = ""
    @State private var isChecking   = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.tokyoPalette) private var tokyo

    private static func resolveRepoPath() -> String? {
        if let embedded = Bundle.main.infoDictionary?["SourceRepoPath"] as? String {
            let gitDir = URL(fileURLWithPath: embedded).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) { return embedded }
        }
        let bundle = Bundle.main.bundlePath
        var url = URL(fileURLWithPath: bundle)
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            let gitDir = url.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) { return url.path }
        }
        return nil
    }

    private func checkForUpdates() {
        isChecking = true; updateStatus = ""
        DispatchQueue.global().async {
            guard let path = Self.resolveRepoPath() else {
                DispatchQueue.main.async { self.isChecking = false; self.updateStatus = "✗ Git repo not found. Reinstall from source." }
                return
            }
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
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.callout)
                    Text("Back")
                        .font(.callout)
                }
                .foregroundColor(tokyo?.accent ?? Color.accentColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .onTapGesture { monitor.currentView = .history }
                .cursor(.pointingHand)

                Spacer()

                Text("Settings")
                    .font(.headline)
                    .foregroundColor(tokyo?.fg ?? Color.primary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
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

                    settingSection("HISTORY") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Keep last")
                                .font(.callout)
                                .foregroundColor(tokyo?.fg ?? Color.primary)
                            Picker("Keep last", selection: $monitor.historyLimit) {
                                Text("10 items").tag(10)
                                Text("50 items").tag(50)
                                Text("100 items").tag(100)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    settingSection("APPEARANCE") {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Color scheme")
                                    .font(.callout)
                                    .foregroundColor(tokyo?.fg ?? Color.primary)
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
                                    .foregroundColor(tokyo?.fg ?? Color.primary)
                                Picker("Preset", selection: $monitor.appPreset) {
                                    Text("Default").tag("default")
                                    Text("Tokyo Night").tag("tokyoNight")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                if monitor.appPreset == "tokyoNight" {
                                    Text("Auto-switches background between light and dark palettes")
                                        .font(.caption2)
                                        .foregroundColor(tokyo?.comment ?? Color.secondary)
                                }
                            }
                        }
                    }

                    settingSection("GENERAL") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Launch at Login", isOn: $launchAtLogin)
                                .font(.callout)
                                .foregroundColor(tokyo?.fg ?? Color.primary)
                                .onChange(of: launchAtLogin) { newValue in
                                    do {
                                        if newValue { try SMAppService.mainApp.register() }
                                        else { try SMAppService.mainApp.unregister() }
                                    } catch {
                                        launchAtLogin = !newValue
                                    }
                                }
                        }
                    }

                    settingSection("PRIVACY") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Hide passwords & secrets", isOn: $monitor.passwordDetectionEnabled)
                                .font(.callout)
                                .foregroundColor(tokyo?.fg ?? Color.primary)
                            Text("Detected secrets are stored but hidden. Toggle off to reveal all.")
                                .font(.caption2)
                                .foregroundColor(tokyo?.comment ?? Color.secondary)

                            Toggle("Auto-clear entries older than 30 days", isOn: $monitor.autoClearEnabled)
                                .font(.callout)
                                .foregroundColor(tokyo?.fg ?? Color.primary)
                        }
                    }

                    settingSection("UPDATES") {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                checkForUpdates()
                            } label: {
                                Text(isChecking ? "Checking…" : "Check for Updates")
                                    .foregroundColor(tokyo?.fg ?? Color.primary)
                            }
                            .disabled(isChecking)
                            if !updateStatus.isEmpty {
                                Text(updateStatus)
                                    .font(.caption)
                                    .foregroundColor(tokyo?.comment ?? Color.secondary)
                            }
                        }
                    }

                    settingSection("ABOUT") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("PrivateCopyClip v3.0")
                                    .font(.callout)
                                    .foregroundColor(tokyo?.fg ?? Color.primary)
                                Spacer()
                                Link("Changelog ↗", destination: URL(string: "https://github.com/BogdanAlinTudorache/PrivateCopyClip/commits/main/")!)
                                    .font(.caption)
                            }
                            Text("All data is stored locally on your Mac. Nothing leaves your device.")
                                .font(.caption)
                                .foregroundColor(tokyo?.comment ?? Color.secondary)
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
                    .foregroundColor(tokyo?.comment ?? Color.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .frame(width: AppLayout.width, height: AppLayout.height)
    }

    @ViewBuilder
    private func settingSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(tokyo?.accent ?? Color.secondary)
            content()
        }
    }
}

// MARK: - Content View (router + theme)

struct ContentView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @Environment(\.colorScheme) var colorScheme

    private var resolvedScheme: ColorScheme? {
        let t = AppTheme(rawValue: monitor.appTheme) ?? .system
        return t.colorScheme
    }

    private var effectiveColorScheme: ColorScheme {
        resolvedScheme ?? colorScheme
    }

    private var palette: TokyoPalette? {
        guard monitor.appPreset == "tokyoNight" else { return nil }
        return effectiveColorScheme == .dark ? .dark : .light
    }

    var body: some View {
        Group {
            switch monitor.currentView {
            case .history: ClipboardHistoryView(monitor: monitor)
            case .settings: SettingsView(monitor: monitor)
            }
        }
        .environment(\.tokyoPalette, palette)
        .background(palette?.bg ?? .clear)
        .preferredColorScheme(resolvedScheme)
        .onAppear { applyAppKitAppearance() }
        .onChange(of: monitor.appTheme) { _ in applyAppKitAppearance() }
    }

    private func applyAppKitAppearance() {
        let t = AppTheme(rawValue: monitor.appTheme) ?? .system
        switch t {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:  NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
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
        ZStack(alignment: .topTrailing) {
            Image(systemName: "paperclip")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .medium))
            if monitor.entries.count > 0 {
                Text("\(min(monitor.entries.count, 99))")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.secondary.opacity(0.3)))
                    .offset(x: 6, y: -4)
            }
        }
    }
}
