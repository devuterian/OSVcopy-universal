import XCTest
@testable import OSVcopy

final class MediaOrganizerScanTests: XCTestCase {
    func testIterMediaFilesUnderScansEveryQueuedFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OSVcopyTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let firstFile = first.appendingPathComponent("CAM_20260101000000_A.MP4")
        let secondFile = second.appendingPathComponent("CAM_20260102000000_B.MP4")
        try Data([0x01]).write(to: firstFile)
        try Data([0x02]).write(to: secondFile)

        let result = MediaOrganizer.iterMediaFilesUnder(
            entries: [first, second],
            includeHidden: false,
            allowedExtensions: ["mp4"]
        )

        XCTAssertFalse(result.abortedByCancellation)
        XCTAssertEqual(Set(result.mediaFiles.map(\.lastPathComponent)), [
            firstFile.lastPathComponent,
            secondFile.lastPathComponent,
        ])
    }

    func testIterMediaFilesUnderContinuesAfterMissingQueuedFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OSVcopyTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let media = folder.appendingPathComponent("CAM_20260103000000_C.MP4")
        try Data([0x03]).write(to: media)

        let result = MediaOrganizer.iterMediaFilesUnder(
            entries: [
                root.appendingPathComponent("missing", isDirectory: true),
                folder,
            ],
            includeHidden: false,
            allowedExtensions: ["mp4"]
        )

        XCTAssertFalse(result.abortedByCancellation)
        XCTAssertEqual(result.mediaFiles.map(\.lastPathComponent), [media.lastPathComponent])
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testDuplicateCheckModeCanUseFileSizeOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OSVcopyTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let destBase = root.appendingPathComponent("dest", isDirectory: true)
        let destDay = destBase.appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("2026-01-01", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDay, withIntermediateDirectories: true)

        let name = "CAM_20260101000000_A.MP4"
        let source = sourceDir.appendingPathComponent(name)
        let existingDest = destDay.appendingPathComponent(name)
        try Data([0x01, 0x02, 0x03]).write(to: source)
        try Data([0x09, 0x08, 0x07]).write(to: existingDest)

        let md5Result = MediaOrganizer.organizeFile(
            source: source,
            destBase: destBase,
            layout: .yearThenDate,
            copyMode: true,
            dryRun: true,
            duplicateCheckMode: .md5,
            allowedExtensions: ["mp4"]
        )

        XCTAssertTrue(md5Result.ok)
        XCTAssertFalse(md5Result.skippedDuplicate)
        XCTAssertEqual(md5Result.destFile?.lastPathComponent, "CAM_20260101000000_A_1.MP4")

        let sizeOnlyResult = MediaOrganizer.organizeFile(
            source: source,
            destBase: destBase,
            layout: .yearThenDate,
            copyMode: true,
            dryRun: true,
            duplicateCheckMode: .fileSizeOnly,
            allowedExtensions: ["mp4"]
        )

        XCTAssertTrue(sizeOnlyResult.ok)
        XCTAssertTrue(sizeOnlyResult.skippedDuplicate)
        XCTAssertEqual(sizeOnlyResult.destFile, existingDest)
        XCTAssertTrue(sizeOnlyResult.message.contains("파일 크기 동일"))
    }
}
