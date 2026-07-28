import AppKit
import Combine
import SwiftUI

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class OrganizerViewModel: ObservableObject {
    private static let userCancellationLogLine = "— 사용자 취소 —"

    enum Phase: String {
        case idle
        case scanning
        case organizing
        case done
        case cancelled
    }

    @Published var queue: [QueueItem] = []
    @Published var destBasePath: String = UserDefaults.standard.string(forKey: "destBasePath") ?? ""
    @Published var folderLayout: FolderLayout = .yearThenDate
    @Published var copyMode: Bool = UserDefaults.standard.object(forKey: "copyMode") as? Bool ?? true
    @Published var previewOnly: Bool = UserDefaults.standard.bool(forKey: "previewOnly")
    @Published var includeHiddenInScan: Bool = UserDefaults.standard.bool(forKey: "includeHiddenInScan")
    @Published var duplicateCheckMode: DuplicateCheckMode = .md5
    @Published var selectedMediaExtensions: Set<String> = OrganizerViewModel.loadSelectedMediaExtensions()

    @Published var phase: Phase = .idle
    @Published var filesDone: Int = 0
    @Published var filesTotal: Int = 0
    @Published var bytesDone: Int64 = 0
    @Published var bytesTotal: Int64 = 0
    @Published var currentFileName: String = ""
    @Published var instantMBps: Double = 0
    @Published var averageMBps: Double = 0
    @Published var etaText: String?
    @Published var logLines: [String] = []
    @Published var errorBanner: String?

    private var organizeTask: Task<Void, Never>?

    private static let selectedMediaExtensionsKey = "selectedMediaExtensions"
    init() {
        if let raw = UserDefaults.standard.string(forKey: "folderLayout"),
           let l = FolderLayout(rawValue: raw) {
            folderLayout = l
        }
        if let raw = UserDefaults.standard.string(forKey: "duplicateCheckMode"),
           let mode = DuplicateCheckMode(rawValue: raw) {
            duplicateCheckMode = mode
        }
    }

    private static func loadSelectedMediaExtensions() -> Set<String> {
        guard let stored = UserDefaults.standard.array(forKey: selectedMediaExtensionsKey) as? [String] else {
            return MediaOrganizer.mediaExtensions
        }
        let normalized = MediaOrganizer.normalizedExtensions(Set(stored))
        return normalized.isEmpty ? MediaOrganizer.mediaExtensions : normalized
    }

    func saveSettings() {
        UserDefaults.standard.set(destBasePath, forKey: "destBasePath")
        UserDefaults.standard.set(folderLayout.rawValue, forKey: "folderLayout")
        UserDefaults.standard.set(copyMode, forKey: "copyMode")
        UserDefaults.standard.set(previewOnly, forKey: "previewOnly")
        UserDefaults.standard.set(includeHiddenInScan, forKey: "includeHiddenInScan")
        UserDefaults.standard.set(duplicateCheckMode.rawValue, forKey: "duplicateCheckMode")
        UserDefaults.standard.set(MediaOrganizer.sortedMediaExtensions.filter { selectedMediaExtensions.contains($0) }, forKey: Self.selectedMediaExtensionsKey)
    }

    func setAllMediaExtensions(_ selected: Bool) {
        selectedMediaExtensions = selected ? MediaOrganizer.mediaExtensions : []
        saveSettings()
    }

    func setMediaExtension(_ ext: String, selected: Bool) {
        let normalized = MediaOrganizer.normalizedExtensions([ext])
        guard let ext = normalized.first else { return }
        if selected {
            selectedMediaExtensions.insert(ext)
        } else {
            selectedMediaExtensions.remove(ext)
        }
        saveSettings()
    }

    func appendQueue(urls: [URL]) {
        for u in urls {
            let std = MediaOrganizer.sanitizeQueuedURL(u)
            if queue.contains(where: { $0.url.path == std.path }) { continue }
            queue.append(QueueItem(url: std))
        }
    }

    func removeQueue(ids: Set<QueueItem.ID>) {
        queue.removeAll { ids.contains($0.id) }
    }

    func clearQueue() {
        queue.removeAll()
    }

    func cancelOrganize() {
        organizeTask?.cancel()
        guard phase == .scanning || phase == .organizing else { return }
        phase = .cancelled
        DockTileProgress.setActive(false, progress: 0, indeterminate: false)
        appendUserCancellationLogIfNeeded()
    }

    var fileProgress: Double {
        guard filesTotal > 0 else { return 0 }
        return Double(filesDone) / Double(filesTotal)
    }

    private func appendLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }

    private func appendUserCancellationLogIfNeeded() {
        if logLines.last == Self.userCancellationLogLine { return }
        appendLog(Self.userCancellationLogLine)
    }

    nonisolated private func applyCooperativeCancellation() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.phase = .cancelled
            DockTileProgress.setActive(false, progress: 0, indeterminate: false)
            self.appendUserCancellationLogIfNeeded()
        }
    }

    private func formatETA(_ sec: TimeInterval) -> String {
        if sec.isNaN || sec.isInfinite || sec > 86400 * 7 { return "—" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d시간 %d분", h, mm)
        }
        if m > 0 {
            return String(format: "%d분 %d초", m, s)
        }
        return String(format: "%d초", max(1, s))
    }

    func runOrganize() {
        errorBanner = nil
        guard organizeTask == nil else { return }
        let destRaw = destBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destRaw.isEmpty else {
            errorBanner = "대상 라이브러리 폴더를 입력하세요."
            return
        }
        let destExpanded = (destRaw as NSString).expandingTildeInPath
        let destClean = MediaOrganizer.sanitizeFilePathString(destExpanded)
        let destURL = URL(fileURLWithPath: destClean, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destURL.path, isDirectory: &isDir), isDir.boolValue else {
            errorBanner = "대상 폴더가 없거나 폴더가 아닙니다."
            return
        }
        guard !queue.isEmpty else {
            errorBanner = "대기열에 파일 또는 폴더를 추가하세요."
            return
        }
        guard !selectedMediaExtensions.isEmpty else {
            errorBanner = "복사할 확장자를 하나 이상 선택하세요."
            return
        }

        saveSettings()
        OrganizeNotifications.requestAuthorizationIfNeeded()
        let entries = queue.map(\.url)
        let layout = folderLayout
        let copy = copyMode
        let dry = previewOnly
        let includeHidden = includeHiddenInScan
        let duplicateMode = duplicateCheckMode
        let allowedExtensions = selectedMediaExtensions

        organizeTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.runOrganizeWork(
                entries: entries,
                destURL: destURL,
                layout: layout,
                copyMode: copy,
                dryRun: dry,
                includeHidden: includeHidden,
                duplicateCheckMode: duplicateMode,
                allowedExtensions: allowedExtensions
            )
            await MainActor.run { [weak self] in
                self?.organizeTask = nil
            }
        }
    }

    private nonisolated func runOrganizeWork(
        entries: [URL],
        destURL: URL,
        layout: FolderLayout,
        copyMode: Bool,
        dryRun: Bool,
        includeHidden: Bool,
        duplicateCheckMode: DuplicateCheckMode,
        allowedExtensions: Set<String>
    ) async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.phase = .scanning
            self.filesDone = 0
            self.filesTotal = 0
            self.bytesDone = 0
            self.bytesTotal = 0
            self.currentFileName = ""
            self.instantMBps = 0
            self.averageMBps = 0
            self.etaText = nil
            self.appendLog("— 스캔 시작 —")
            self.appendLog("대기열 \(entries.count)개 검사")
            for entry in entries {
                self.appendLog("• \(entry.path)")
            }
            DockTileProgress.setActive(true, progress: 0, indeterminate: true)
        }

        if Task.isCancelled {
            await applyCooperativeCancellation()
            return
        }

        let scanResult = MediaOrganizer.iterMediaFilesUnder(
            entries: entries,
            includeHidden: includeHidden,
            allowedExtensions: allowedExtensions,
            isCancelled: { Task.isCancelled }
        )
        if scanResult.abortedByCancellation {
            await applyCooperativeCancellation()
            return
        }
        let mediaList = scanResult.mediaFiles

        await MainActor.run { [weak self] in
            self?.appendLog("미디어 \(mediaList.count)개 발견")
            for warning in scanResult.warnings {
                self?.appendLog("⚠︎ \(warning)")
            }
        }

        var sizes: [Int64] = []
        sizes.reserveCapacity(mediaList.count)
        var total: Int64 = 0
        let sizeCancelStride = 16
        for (i, u) in mediaList.enumerated() {
            if i % sizeCancelStride == 0, Task.isCancelled {
                await applyCooperativeCancellation()
                return
            }
            let sz = MediaOrganizer.fileSize(at: u)
            sizes.append(sz)
            total += sz
            if i % 32 == 0 {
                let name = u.lastPathComponent
                await MainActor.run { [weak self] in
                    self?.currentFileName = name
                }
            }
            if i % 64 == 0 {
                await Task.yield()
            }
        }

        if Task.isCancelled {
            await applyCooperativeCancellation()
            return
        }

        let totalSnapshot = total
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.filesTotal = mediaList.count
            self.bytesTotal = totalSnapshot
            self.phase = .organizing
            self.appendLog("— 정리 시작 —")
            DockTileProgress.setActive(true, progress: 0, indeterminate: false)
        }

        var metrics = TransferMetrics()
        metrics.beginOrganize()
        var ok = 0
        var fail = 0
        var skipped = 0
        var bytesDoneLocal: Int64 = 0
        var lastMetricsFlush = Date.distantPast

        let onByteDelta: ((Int64) -> Void)? = (!dryRun && copyMode)
            ? { delta in
                metrics.recordBytesDelta(delta, at: Date())
                bytesDoneLocal += delta
                let now = Date()
                guard now.timeIntervalSince(lastMetricsFlush) >= 0.1 else { return }
                lastMetricsFlush = now
                let inst = metrics.instantaneousBps() / (1024 * 1024)
                let avg = metrics.averageBps(at: now) / (1024 * 1024)
                let remaining = max(0, totalSnapshot - bytesDoneLocal)
                let etaStr: String? = {
                    guard let eta = metrics.estimatedRemainingSeconds(remainingBytes: remaining, at: now) else {
                        return nil
                    }
                    let sec = eta
                    if sec.isNaN || sec.isInfinite || sec > 86400 * 7 { return "—" }
                    let m = Int(sec) / 60
                    let s = Int(sec) % 60
                    if m >= 60 {
                        let h = m / 60
                        let mm = m % 60
                        return String(format: "%d시간 %d분", h, mm)
                    }
                    if m > 0 {
                        return String(format: "%d분 %d초", m, s)
                    }
                    return String(format: "%d초", max(1, s))
                }()
                let bytesSnap = bytesDoneLocal
                let instSnap = inst
                let avgSnap = avg
                let etaSnap = etaStr
                let totalB = totalSnapshot
                Task { @MainActor [weak self] in
                    let frac = totalB > 0 ? Double(bytesSnap) / Double(totalB) : 0
                    DockTileProgress.setActive(true, progress: frac, indeterminate: false)
                    self?.bytesDone = bytesSnap
                    self?.instantMBps = instSnap
                    self?.averageMBps = avgSnap
                    self?.etaText = etaSnap
                }
            }
            : nil

        for (idx, src) in mediaList.enumerated() {
            if Task.isCancelled {
                await applyCooperativeCancellation()
                return
            }

            let name = src.lastPathComponent

            await MainActor.run { [weak self] in
                self?.currentFileName = name
                self?.filesDone = idx
            }

            let result = MediaOrganizer.organizeFile(
                source: src,
                destBase: destURL,
                layout: layout,
                copyMode: copyMode,
                dryRun: dryRun,
                duplicateCheckMode: duplicateCheckMode,
                allowedExtensions: allowedExtensions,
                isCancelled: { Task.isCancelled },
                onByteDelta: onByteDelta
            )

            if !result.ok, result.message == "취소됨" {
                await applyCooperativeCancellation()
                return
            }

            if result.ok {
                ok += 1
                if result.skippedDuplicate {
                    skipped += 1
                }
                if !dryRun {
                    if !result.bytesCountedInStreaming {
                        metrics.recordFileCompleted(size: result.processedBytes)
                        bytesDoneLocal += result.processedBytes
                    }
                    let now = Date()
                    let inst = metrics.instantaneousBps() / (1024 * 1024)
                    let avg = metrics.averageBps(at: now) / (1024 * 1024)
                    let remaining = max(0, totalSnapshot - bytesDoneLocal)
                    let etaStr: String? = {
                        guard let eta = metrics.estimatedRemainingSeconds(remainingBytes: remaining, at: now) else {
                            return nil
                        }
                        let sec = eta
                        if sec.isNaN || sec.isInfinite || sec > 86400 * 7 { return "—" }
                        let m = Int(sec) / 60
                        let s = Int(sec) % 60
                        if m >= 60 {
                            let h = m / 60
                            let mm = m % 60
                            return String(format: "%d시간 %d분", h, mm)
                        }
                        if m > 0 {
                            return String(format: "%d분 %d초", m, s)
                        }
                        return String(format: "%d초", max(1, s))
                    }()
                    let bytesSnap = bytesDoneLocal
                    let instSnap = inst
                    let avgSnap = avg
                    let etaSnap = etaStr
                    let totalB = totalSnapshot
                    await MainActor.run { [weak self] in
                        self?.bytesDone = bytesSnap
                        self?.instantMBps = instSnap
                        self?.averageMBps = avgSnap
                        self?.etaText = etaSnap
                        if totalB > 0 {
                            DockTileProgress.setActive(true, progress: Double(bytesSnap) / Double(totalB), indeterminate: false)
                        }
                    }
                }
                await MainActor.run { [weak self] in
                    self?.appendLog("✓ \(name): \(result.message)")
                }
            } else {
                fail += 1
                await MainActor.run { [weak self] in
                    self?.appendLog("✗ \(name): \(result.message)")
                }
            }

            await MainActor.run { [weak self] in
                self?.filesDone = idx + 1
            }
        }

        let okSnap = ok
        let failSnap = fail
        let skippedSnap = skipped
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.instantMBps = 0
            self.phase = .done
            DockTileProgress.setActive(false, progress: 0, indeterminate: false)
            self.appendLog("— 완료: 성공 \(okSnap), 건너뜀 \(skippedSnap), 실패 \(failSnap) —")
            OrganizeNotifications.notifyFinished(success: okSnap, skipped: skippedSnap, failed: failSnap, preview: self.previewOnly)
            if !self.previewOnly {
                self.queue.removeAll()
            }
        }
    }
}

enum OpenPanelHelper {
    @MainActor
    static func pickFiles() -> [URL] {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        p.title = "미디어 파일 선택"
        guard p.runModal() == .OK else { return [] }
        return p.urls
    }

    @MainActor
    static func pickFolders() -> [URL] {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        p.title = "폴더 선택"
        guard p.runModal() == .OK else { return [] }
        return p.urls
    }

    @MainActor
    static func pickDestLibrary() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.title = "대상 라이브러리"
        guard p.runModal() == .OK else { return nil }
        return p.url
    }
}
