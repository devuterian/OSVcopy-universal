import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: OrganizerViewModel
    @State private var selection = Set<QueueItem.ID>()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("대기열") {
                    if model.queue.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("항목 없음")
                                .font(.headline)
                            Text("파일·폴더를 추가하거나 여기로 드래그하세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding()
                    } else {
                        ForEach(model.queue) { item in
                            let isDir = (try? item.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                            Label(item.url.path, systemImage: isDir ? "folder.fill" : "doc.fill")
                                .lineLimit(2)
                                .tag(item.id)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
            .toolbar {
                ToolbarItemGroup {
                    Button("파일", systemImage: "doc.badge.plus") {
                        model.appendQueue(urls: OpenPanelHelper.pickFiles())
                    }
                    .help("파일 추가")
                    Button("폴더", systemImage: "folder.badge.plus") {
                        model.appendQueue(urls: OpenPanelHelper.pickFolders())
                    }
                    .help("폴더 추가")
                }
                ToolbarItemGroup {
                    Button("제거", systemImage: "minus.circle") {
                        model.removeQueue(ids: selection)
                        selection.removeAll()
                    }
                    .disabled(selection.isEmpty)
                    Button("비우기", systemImage: "trash") {
                        model.clearQueue()
                        selection.removeAll()
                    }
                    .disabled(model.queue.isEmpty)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                Task { @MainActor in
                    let urls = await collectURLs(from: providers)
                    model.appendQueue(urls: urls)
                }
                return true
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("OSVcopy")
                        .font(.largeTitle.weight(.semibold))

                    Text("OSV·INSV·MP4·RAW·JPEG 등을 촬영일 기준으로 라이브러리 폴더에 정리합니다. ffprobe는 Homebrew 등으로 설치된 경로를 사용합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let err = model.errorBanner {
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    GroupBox("대상 라이브러리") {
                        HStack {
                            TextField("/Volumes/… 또는 홈 경로", text: $model.destBasePath)
                                .textFieldStyle(.roundedBorder)
                            Button("선택…") {
                                if let u = OpenPanelHelper.pickDestLibrary() {
                                    model.destBasePath = u.path
                                }
                            }
                        }
                    }

                    GroupBox("옵션") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("폴더 구조", selection: $model.folderLayout) {
                                ForEach(FolderLayout.allCases) { layout in
                                    Text(layout.title).tag(layout)
                                }
                            }
                            .pickerStyle(.radioGroup)

                            Picker("중복 검사", selection: $model.duplicateCheckMode) {
                                ForEach(DuplicateCheckMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)

                            Toggle("복사 (원본 유지)", isOn: $model.copyMode)
                            Toggle("미리보기만 (디스크에 쓰지 않음)", isOn: $model.previewOnly)
                            Toggle("숨김 폴더까지 스캔", isOn: $model.includeHiddenInScan)
                        }
                    }

                    GroupBox("복사할 확장자") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(model.selectedMediaExtensions.count) / \(MediaOrganizer.mediaExtensions.count)개 선택")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("전체 선택") {
                                    model.setAllMediaExtensions(true)
                                }
                                Button("전체 해제") {
                                    model.setAllMediaExtensions(false)
                                }
                                .disabled(model.selectedMediaExtensions.isEmpty)
                            }

                            ForEach(MediaOrganizer.mediaExtensionGroups, id: \.title) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 6) {
                                        ForEach(group.extensions, id: \.self) { ext in
                                            Toggle(".\(ext.uppercased())", isOn: Binding(
                                                get: { model.selectedMediaExtensions.contains(ext) },
                                                set: { model.setMediaExtension(ext, selected: $0) }
                                            ))
                                            .toggleStyle(.checkbox)
                                            .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    OrganizeProgressPanel(
                        phase: model.phase,
                        fileProgress: model.fileProgress,
                        filesDone: model.filesDone,
                        filesTotal: model.filesTotal,
                        bytesDone: model.bytesDone,
                        bytesTotal: model.bytesTotal,
                        currentFileName: model.currentFileName,
                        instantMBps: model.instantMBps,
                        averageMBps: model.averageMBps,
                        etaText: model.etaText
                    )

                    if model.phase == .scanning || model.phase == .organizing {
                        HStack {
                            Button(role: .cancel) {
                                model.cancelOrganize()
                            } label: {
                                Label("취소", systemImage: "xmark.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .keyboardShortcut(.escape, modifiers: [])
                            Spacer()
                        }
                    }

                    GroupBox("로그") {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(minHeight: 120, maxHeight: 220)
                            .onChange(of: model.logLines.count) { _ in
                                if let last = model.logLines.indices.last {
                                    withAnimation {
                                        proxy.scrollTo(last, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("정리 실행") {
                            model.runOrganize()
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.phase == .scanning || model.phase == .organizing)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("OSVcopy")
    }

    private func collectURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self, returning: [URL].self) { group in
            for p in providers {
                group.addTask {
                    await withCheckedContinuation { cont in
                        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            if let url = item as? URL {
                                cont.resume(returning: url)
                            } else if let data = item as? Data, let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                cont.resume(returning: URL(fileURLWithPath: s))
                            } else {
                                cont.resume(returning: nil)
                            }
                        }
                    }
                }
            }
            var out: [URL] = []
            for await u in group {
                if let u { out.append(u) }
            }
            return out
        }
    }
}
