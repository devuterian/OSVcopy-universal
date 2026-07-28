import AppKit
import CryptoKit
import Foundation
import ImageIO

enum FolderLayout: String, CaseIterable, Identifiable, Hashable {
    case yearThenDate = "year_then_date"
    case flatDate = "flat_date"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yearThenDate: return "연도 / 날짜 (dslr/2026/2026-01-18/…)"
        case .flatDate: return "날짜만 (dslr/2026-01-18/…)"
        }
    }
}

enum DuplicateCheckMode: String, CaseIterable, Identifiable, Hashable {
    case md5 = "md5"
    case fileSizeOnly = "file_size_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .md5: return "MD5 검사 (정확)"
        case .fileSizeOnly: return "파일 크기만 검사 (빠름)"
        }
    }

    var duplicateLabel: String {
        switch self {
        case .md5: return "MD5 동일"
        case .fileSizeOnly: return "파일 크기 동일"
        }
    }
}

struct OrganizeResult: Sendable {
    let ok: Bool
    let message: String
    let source: URL
    let destFile: URL?
    let skippedDuplicate: Bool
    let processedBytes: Int64
    /// true면 `onByteDelta`로 이미 바이트·속도 메트릭에 반영됨(이중 합산 금지).
    let bytesCountedInStreaming: Bool
}

struct MediaScanResult: Sendable {
    let mediaFiles: [URL]
    let warnings: [String]
    /// 디렉터리 순회 중 `isCancelled()`가 true여서 목록이 완전하지 않을 수 있음.
    let abortedByCancellation: Bool
}

enum MediaOrganizerError: LocalizedError {
    case notAFile
    case unsupportedExtension
    case couldNotResolveDate(URL)
    case samePath

    var errorDescription: String? {
        switch self {
        case .notAFile: return "파일이 아닙니다."
        case .unsupportedExtension: return "지원하지 않는 확장자입니다."
        case .couldNotResolveDate(let u): return "날짜를 알 수 없습니다: \(u.lastPathComponent)"
        case .samePath: return "원본과 동일한 경로입니다."
        }
    }
}

enum MediaOrganizer {
    private static let folderUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func ffprobeExecutable() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe",
        ]
        let fm = FileManager.default
        for p in candidates where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    static let mediaExtensions: Set<String> = [
        "osv", "insv", "mp4", "mov", "m4v", "avi", "mkv", "webm",
        "jpg", "jpeg", "jfif", "png", "heic", "heif", "tif", "tiff", "bmp", "webp",
        "dng", "arw", "cr2", "cr3", "nef", "nrw", "orf", "raf", "rw2", "pef", "srw",
        "3fr", "erf", "mrw", "raw", "rwl", "x3f",
    ]

    static let mediaExtensionGroups: [(title: String, extensions: [String])] = [
        ("360 / 동영상", ["osv", "insv", "mp4", "mov", "m4v", "avi", "mkv", "webm"]),
        ("이미지", ["jpg", "jpeg", "jfif", "png", "heic", "heif", "tif", "tiff", "bmp", "webp"]),
        ("RAW", ["dng", "arw", "cr2", "cr3", "nef", "nrw", "orf", "raf", "rw2", "pef", "srw", "3fr", "erf", "mrw", "raw", "rwl", "x3f"]),
    ]

    static var sortedMediaExtensions: [String] {
        mediaExtensionGroups.flatMap(\.extensions)
    }

    private static let camRegex: NSRegularExpression = {
        let p = #"^CAM_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_"#
        return try! NSRegularExpression(pattern: p, options: .caseInsensitive)
    }()

    static func normalizedExtensions(_ extensions: Set<String>) -> Set<String> {
        Set(extensions.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines)).lowercased() })
            .intersection(mediaExtensions)
    }

    static func isMediaFile(_ url: URL, allowedExtensions: Set<String> = mediaExtensions) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && allowedExtensions.contains(ext)
    }

    /// QSpace Pro 등에서 `URL.path`가 `/file:/Volumes/...`처럼 잘못 붙는 경우를 실제 POSIX 경로로 고칩니다.
    static func sanitizeFilePathString(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while p.hasPrefix("/file:") {
            p = String(p.dropFirst(6))
            while p.hasPrefix("//") {
                p.removeFirst()
            }
            if !p.hasPrefix("/") {
                p = "/" + p
            }
        }
        while p.hasPrefix("file:") {
            if let u = URL(string: p), u.scheme == "file", !u.path.isEmpty {
                p = u.path
                continue
            }
            if let r = p.range(of: "file:") {
                var rest = String(p[r.upperBound...])
                while rest.first == "/" {
                    rest.removeFirst()
                }
                p = "/" + rest
                continue
            }
            break
        }
        return p
    }

    /// 대기열·드롭으로 들어온 파일 URL을 로컬 디스크 경로로 정규화합니다.
    static func sanitizeQueuedURL(_ url: URL) -> URL {
        let cleaned = sanitizeFilePathString(url.path)
        return URL(fileURLWithPath: cleaned).standardizedFileURL
    }

    /// `isCancelled`는 대략 `batchSize` 단위(디렉터리 항목 처리 횟수)마다 호출됩니다.
    static func iterMediaFilesUnder(
        entries: [URL],
        includeHidden: Bool,
        allowedExtensions: Set<String> = mediaExtensions,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        batchSize: Int = 256
    ) -> MediaScanResult {
        let allowedExtensions = normalizedExtensions(allowedExtensions)
        var seen = Set<String>()
        var out: [URL] = []
        var warnings: [String] = []
        let fm = FileManager.default
        var visitedDirs = Set<String>()
        var workSteps = 0

        func noteProgressAndShouldAbort() -> Bool {
            workSteps += 1
            if workSteps % batchSize == 0, isCancelled() { return true }
            return false
        }

        func addMediaFile(_ url: URL) {
            let key = url.resolvingSymlinksInPath().path
            if seen.insert(key).inserted {
                out.append(url)
            }
        }

        let propKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .nameKey]
        for rawIn in entries {
            if noteProgressAndShouldAbort() {
                return MediaScanResult(
                    mediaFiles: out.sorted { $0.path.lowercased() < $1.path.lowercased() },
                    warnings: warnings,
                    abortedByCancellation: true
                )
            }
            let raw = sanitizeQueuedURL(rawIn)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: raw.path, isDirectory: &isDir) else {
                warnings.append("스캔 항목 없음: \(raw.path)")
                continue
            }
            let url = raw.standardizedFileURL

            if !isDir.boolValue {
                if isMediaFile(url, allowedExtensions: allowedExtensions) {
                    addMediaFile(url)
                }
                continue
            }

            let rootKey = url.resolvingSymlinksInPath().path
            guard visitedDirs.insert(rootKey).inserted else { continue }

            var dirStack = [url]
            while let currentDir = dirStack.popLast() {
                if noteProgressAndShouldAbort() {
                    return MediaScanResult(
                        mediaFiles: out.sorted { $0.path.lowercased() < $1.path.lowercased() },
                        warnings: warnings,
                        abortedByCancellation: true
                    )
                }
                do {
                    let children = try fm.contentsOfDirectory(at: currentDir, includingPropertiesForKeys: propKeys, options: [])
                    for item in children.sorted(by: { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }) {
                        if noteProgressAndShouldAbort() {
                            return MediaScanResult(
                                mediaFiles: out.sorted { $0.path.lowercased() < $1.path.lowercased() },
                                warnings: warnings,
                                abortedByCancellation: true
                            )
                        }
                        let rv = try? item.resourceValues(forKeys: Set(propKeys))
                        let isHidden = rv?.isHidden ?? item.lastPathComponent.hasPrefix(".")
                        if !includeHidden && isHidden {
                            continue
                        }

                        if rv?.isDirectory == true {
                            let dirKey = item.resolvingSymlinksInPath().path
                            if visitedDirs.insert(dirKey).inserted {
                                dirStack.append(item)
                            }
                            continue
                        }
                        if rv?.isRegularFile != true {
                            continue
                        }
                        guard isMediaFile(item, allowedExtensions: allowedExtensions) else { continue }
                        addMediaFile(item)
                    }
                } catch {
                    warnings.append("스캔 건너뜀(권한/오류): \(currentDir.path) (\(error.localizedDescription))")
                }
            }
        }
        return MediaScanResult(
            mediaFiles: out.sorted { $0.path.lowercased() < $1.path.lowercased() },
            warnings: warnings,
            abortedByCancellation: false
        )
    }

    static func fileSize(at url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }

    // MARK: - Date resolution

    private static func dateFromBasename(_ url: URL) -> (String, Date)? {
        let name = url.lastPathComponent as NSString
        let range = NSRange(location: 0, length: name.length)
        guard let m = camRegex.firstMatch(in: name as String, options: [], range: range) else { return nil }
        guard m.numberOfRanges >= 7 else { return nil }
        func int(_ i: Int) -> Int {
            (name.substring(with: m.range(at: i)) as NSString).integerValue
        }
        let y = int(1), mo = int(2), d = int(3), h = int(4), mi = int(5), s = int(6)
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        comps.hour = h; comps.minute = mi; comps.second = s
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        guard let dt = Calendar(identifier: .gregorian).date(from: comps) else { return nil }
        let folder = String(format: "%04d-%02d-%02d", y, mo, d)
        return (folder, dt)
    }

    static func parseTagDatetime(_ val: String) -> Date? {
        let v = val.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return nil }

        if v.hasSuffix("Z") {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
            if let d = f.date(from: v) { return d }
            f.formatOptions = [.withInternetDateTime, .withTimeZone]
            if let d = f.date(from: v) { return d }
        }
        if v.contains("T") {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: v) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: v) { return d }
        }

        if v.count >= 19, v[v.index(v.startIndex, offsetBy: 4)] == ":", v[v.index(v.startIndex, offsetBy: 7)] == ":" {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let d = f.date(from: String(v.prefix(19))) { return d }
        }
        if v.count >= 19, v[v.index(v.startIndex, offsetBy: 4)] == "-", v[v.index(v.startIndex, offsetBy: 7)] == "-" {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = f.date(from: String(v.prefix(19))) { return d }
        }
        return nil
    }

    static func dateFromFFprobe(_ url: URL) -> (String, Date)? {
        guard let probe = ffprobeExecutable() else { return nil }
        let p = Process()
        p.executableURL = probe
        p.arguments = [
            "-hide_banner", "-print_format", "json", "-show_format", "-show_streams",
            url.path,
        ]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var candidates: [String] = []
        let formatKeys = [
            "creation_time", "creation_date", "com.apple.quicktime.creationdate",
            "date_time", "modify_date", "modification_date",
        ]
        if let fmt = obj["format"] as? [String: Any], let tags = fmt["tags"] as? [String: Any] {
            for key in formatKeys {
                if let v = tags[key] as? String { candidates.append(v) }
            }
            for (k, val) in tags {
                guard let v = val as? String else { continue }
                let lk = k.lowercased()
                if ["creation_time", "creation_date"].contains(lk) || (lk.contains("creation") && lk.contains("time")) {
                    if !candidates.contains(v) { candidates.append(v) }
                }
            }
        }
        if let streams = obj["streams"] as? [[String: Any]] {
            for stream in streams {
                guard let st = stream["tags"] as? [String: Any] else { continue }
                for (k, val) in st {
                    guard let v = val as? String else { continue }
                    let lk = k.lowercased()
                    if lk.contains("creation_time") || lk == "creation_date" {
                        candidates.append(v)
                    }
                }
            }
        }

        for c in candidates {
            if let dt = parseTagDatetime(c) {
                let folder = folderUTC.string(from: dt)
                return (folder, dt)
            }
        }
        return nil
    }

    static func dateFromImageIO(_ url: URL) -> (String, Date)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        guard let exif = props[kCGImagePropertyExifDictionary] as? [String: Any] else { return nil }

        let keys = ["DateTimeOriginal", "DateTime", "DateTimeDigitized"]
        for key in keys {
            guard let raw = exif[key] else { continue }
            let str: String? = {
                if let s = raw as? String { return s }
                if let b = raw as? Data { return String(data: b, encoding: .utf8) }
                return nil
            }()
            guard var val = str?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty else { continue }
            if val.contains("T") {
                val = val.replacingOccurrences(of: "T", with: " ")
            }
            val = val.replacingOccurrences(of: "-", with: ":")
            if let dt = parseTagDatetime(val) {
                let folder = folderUTC.string(from: dt)
                return (folder, dt)
            }
            if val.count >= 19, val[val.index(val.startIndex, offsetBy: 4)] == ":" {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "yyyy:MM:dd HH:mm:ss"
                if let dt = f.date(from: String(val.prefix(19))) {
                    let folder = folderUTC.string(from: dt)
                    return (folder, dt)
                }
            }
        }
        return nil
    }

    static func dateFromStat(_ url: URL) -> (String, Date)? {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        guard let rv = try? url.resourceValues(forKeys: keys) else { return nil }
        let date: Date
        if let c = rv.creationDate {
            date = c
        } else if let m = rv.contentModificationDate {
            date = m
        } else {
            return nil
        }
        let folder = folderUTC.string(from: date)
        return (folder, date)
    }

    static func resolveDateFolder(_ url: URL) throws -> (day: String, label: String) {
        if let r = dateFromBasename(url) { return (r.0, "filename_cam") }
        if let r = dateFromFFprobe(url) { return (r.0, "ffprobe") }
        if let r = dateFromImageIO(url) { return (r.0, "exif") }
        if let r = dateFromStat(url) { return (r.0, "stat") }
        throw MediaOrganizerError.couldNotResolveDate(url)
    }

    static func destinationDirectory(base: URL, dayYyyyMmDd: String, layout: FolderLayout) -> URL {
        let b = base.standardizedFileURL
        switch layout {
        case .flatDate:
            return b.appendingPathComponent(dayYyyyMmDd, isDirectory: true)
        case .yearThenDate:
            let year = String(dayYyyyMmDd.prefix(4))
            return b.appendingPathComponent(year, isDirectory: true)
                .appendingPathComponent(dayYyyyMmDd, isDirectory: true)
        }
    }

    static func uniqueDestination(_ destFile: URL) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destFile.path) {
            return destFile
        }
        let parent = destFile.deletingLastPathComponent()
        let stem = destFile.deletingPathExtension().lastPathComponent
        let ext = destFile.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        for n in 1..<10_000 {
            let name = "\(stem)_\(n)\(suffix)"
            let cand = parent.appendingPathComponent(name, isDirectory: false)
            if !fm.fileExists(atPath: cand.path) {
                return cand
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private static func md5Hex(for url: URL, chunkSize: Int = 1_048_576) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = Insecure.MD5()
        while true {
            let data = try handle.read(upToCount: chunkSize)
            guard let chunk = data, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func filesAreSame(source: URL, dest: URL, mode: DuplicateCheckMode) -> Bool {
        let srcSize = fileSize(at: source)
        let dstSize = fileSize(at: dest)
        guard srcSize == dstSize else { return false }
        guard mode == .md5 else { return true }
        do {
            return try md5Hex(for: source) == md5Hex(for: dest)
        } catch {
            return false
        }
    }

    private static let streamChunkSize = 8 * 1024 * 1024

    private static func copyFileStreaming(
        from src: URL,
        to dst: URL,
        isCancelled: () -> Bool,
        onByteDelta: (Int64) -> Void
    ) throws {
        let fm = FileManager.default
        if isCancelled() { throw CancellationError() }
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        guard fm.createFile(atPath: dst.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let inHandle = try FileHandle(forReadingFrom: src)
        defer { try? inHandle.close() }
        let outHandle = try FileHandle(forWritingTo: dst)
        defer { try? outHandle.close() }
        while true {
            if isCancelled() {
                try? fm.removeItem(at: dst)
                throw CancellationError()
            }
            let piece = try inHandle.read(upToCount: streamChunkSize)
            guard let data = piece, !data.isEmpty else { break }
            try outHandle.write(contentsOf: data)
            onByteDelta(Int64(data.count))
        }
    }

    static func organizeFile(
        source: URL,
        destBase: URL,
        layout: FolderLayout,
        copyMode: Bool,
        dryRun: Bool,
        duplicateCheckMode: DuplicateCheckMode = .md5,
        allowedExtensions: Set<String> = mediaExtensions,
        isCancelled: @escaping () -> Bool = { false },
        onByteDelta: ((Int64) -> Void)? = nil
    ) -> OrganizeResult {
        let allowedExtensions = normalizedExtensions(allowedExtensions)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir), !isDir.boolValue else {
            return OrganizeResult(ok: false, message: MediaOrganizerError.notAFile.localizedDescription, source: source, destFile: nil, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }
        guard isMediaFile(source, allowedExtensions: allowedExtensions) else {
            return OrganizeResult(ok: false, message: MediaOrganizerError.unsupportedExtension.localizedDescription, source: source, destFile: nil, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }

        let day: String
        let label: String
        do {
            let r = try resolveDateFolder(source)
            day = r.day
            label = r.label
        } catch {
            return OrganizeResult(ok: false, message: error.localizedDescription, source: source, destFile: nil, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }

        let destDir = destinationDirectory(base: destBase, dayYyyyMmDd: day, layout: layout)
        let sourceSize = fileSize(at: source)
        let preferredDest = destDir.appendingPathComponent(source.lastPathComponent, isDirectory: false)

        let srcRes = source.resolvingSymlinksInPath()
        let preferredRes = preferredDest.resolvingSymlinksInPath()
        if srcRes.path == preferredRes.path {
            return OrganizeResult(ok: false, message: MediaOrganizerError.samePath.localizedDescription, source: source, destFile: preferredDest, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }

        if fm.fileExists(atPath: preferredDest.path), filesAreSame(source: source, dest: preferredDest, mode: duplicateCheckMode) {
            let duplicateLabel = duplicateCheckMode.duplicateLabel
            if dryRun {
                return OrganizeResult(
                    ok: true,
                    message: "(미리보기) [\(label)] \(day) ⊘ \(duplicateLabel), 건너뜀: \(preferredDest.path)",
                    source: source,
                    destFile: preferredDest,
                    skippedDuplicate: true,
                    processedBytes: sourceSize,
                    bytesCountedInStreaming: false
                )
            }
            if copyMode {
                return OrganizeResult(
                    ok: true,
                    message: "[\(label)] \(day) ⊘ \(duplicateLabel), 복사 건너뜀: \(preferredDest.path)",
                    source: source,
                    destFile: preferredDest,
                    skippedDuplicate: true,
                    processedBytes: sourceSize,
                    bytesCountedInStreaming: false
                )
            }
            do {
                try fm.removeItem(at: source)
                return OrganizeResult(
                    ok: true,
                    message: "[\(label)] \(day) ⊘ \(duplicateLabel), 원본 삭제(이동 완료): \(preferredDest.path)",
                    source: source,
                    destFile: preferredDest,
                    skippedDuplicate: true,
                    processedBytes: sourceSize,
                    bytesCountedInStreaming: false
                )
            } catch {
                return OrganizeResult(
                    ok: false,
                    message: "중복 감지 후 원본 삭제 실패: \(error.localizedDescription)",
                    source: source,
                    destFile: preferredDest,
                    skippedDuplicate: false,
                    processedBytes: 0,
                    bytesCountedInStreaming: false
                )
            }
        }

        let destFile: URL
        do {
            destFile = try uniqueDestination(preferredDest)
        } catch {
            return OrganizeResult(ok: false, message: error.localizedDescription, source: source, destFile: nil, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }

        let dstRes = destFile.resolvingSymlinksInPath()
        if srcRes.path == dstRes.path {
            return OrganizeResult(ok: false, message: MediaOrganizerError.samePath.localizedDescription, source: source, destFile: destFile, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }

        let msg = "[\(label)] \(day) → \(destFile.path)"

        if dryRun {
            return OrganizeResult(ok: true, message: "(미리보기) \(msg)", source: source, destFile: destFile, skippedDuplicate: false, processedBytes: sourceSize, bytesCountedInStreaming: false)
        }

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            if copyMode {
                if let onDelta = onByteDelta {
                    try copyFileStreaming(from: source, to: destFile, isCancelled: isCancelled, onByteDelta: onDelta)
                    return OrganizeResult(ok: true, message: msg, source: source, destFile: destFile, skippedDuplicate: false, processedBytes: sourceSize, bytesCountedInStreaming: true)
                }
                try fm.copyItem(at: source, to: destFile)
                return OrganizeResult(ok: true, message: msg, source: source, destFile: destFile, skippedDuplicate: false, processedBytes: sourceSize, bytesCountedInStreaming: false)
            }
            try fm.moveItem(at: source, to: destFile)
            return OrganizeResult(ok: true, message: msg, source: source, destFile: destFile, skippedDuplicate: false, processedBytes: sourceSize, bytesCountedInStreaming: false)
        } catch {
            if error is CancellationError {
                return OrganizeResult(ok: false, message: "취소됨", source: source, destFile: destFile, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
            }
            return OrganizeResult(ok: false, message: error.localizedDescription, source: source, destFile: destFile, skippedDuplicate: false, processedBytes: 0, bytesCountedInStreaming: false)
        }
    }
}
