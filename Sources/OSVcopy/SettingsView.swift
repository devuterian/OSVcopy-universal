import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: OrganizerViewModel

    var body: some View {
        Form {
            Section {
                Text("일반 옵션은 메인 창의 **옵션** 박스에서 바꿀 수 있습니다. 설정은 자동으로 저장됩니다.")
                    .foregroundStyle(.secondary)
            }
            Section("스캔") {
                Toggle("숨김 폴더까지 스캔", isOn: $model.includeHiddenInScan)
                Text("활성화하면 .로 시작하는 하위 폴더까지 전부 스캔합니다. 대용량 볼륨에서는 느려질 수 있습니다.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section("도구") {
                LabeledContent("ffprobe") {
                    Text(MediaOrganizer.ffprobeExecutable()?.path ?? "없음 (brew install ffmpeg)")
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 220)
        .navigationTitle("OSVcopy")
    }
}
