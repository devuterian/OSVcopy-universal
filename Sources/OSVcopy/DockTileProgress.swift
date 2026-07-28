import AppKit

/// Dock 아이콘 위에 전체 진행(바이트 기준) 막대를 표시합니다.
@MainActor
enum DockTileProgress {
    private static weak var bar: NSProgressIndicator?
    private static weak var container: NSView?

    static func setActive(_ active: Bool, progress: Double, indeterminate: Bool) {
        let tile = NSApp.dockTile

        if !active {
            tile.contentView = nil
            bar = nil
            container = nil
            tile.display()
            return
        }

        if container == nil || bar == nil {
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            let p = NSProgressIndicator(frame: NSRect(x: 8, y: 10, width: 112, height: 14))
            p.style = .bar
            p.isIndeterminate = false
            p.minValue = 0
            p.maxValue = 1
            p.controlSize = .small
            view.addSubview(p)
            tile.contentView = view
            container = view
            bar = p
        }

        bar?.isIndeterminate = indeterminate
        if !indeterminate {
            bar?.doubleValue = min(1, max(0, progress))
        }
        tile.display()
    }
}
