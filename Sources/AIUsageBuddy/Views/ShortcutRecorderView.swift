import SwiftUI
import AppKit

/// ショートカットのキー記録コントロール。
/// クリックしてフォーカス → キー入力で記録、Esc でキャンセル、Delete で無効化。
/// NSTextField は編集開始時にフィールドエディタへキー入力が流れるため、
/// 生の NSView として keyDown を受け取る。
struct ShortcutRecorderView: View {
    let spec: HotKeySpec
    let onChange: (HotKeySpec) -> Void

    var body: some View {
        RecorderControl(spec: spec, onChange: onChange)
    }
}

private struct RecorderControl: NSViewRepresentable {
    let spec: HotKeySpec
    let onChange: (HotKeySpec) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        RecorderNSView(spec: spec, onChange: onChange)
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.spec = spec
        nsView.onChange = onChange
        nsView.updateDisplay()
    }
}

/// キー記録を受け付けるNSView。修飾キー単独の押下は無視する。
final class RecorderNSView: NSView {

    var spec: HotKeySpec
    var onChange: (HotKeySpec) -> Void

    private let label = NSTextField(labelWithString: "")

    init(spec: HotKeySpec, onChange: @escaping (HotKeySpec) -> Void) {
        self.spec = spec
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        addSubview(label)
        updateDisplay()
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 8, dy: 4)
    }

    /// クリックで記録モード（ファーストレスポンダ）に入る。
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            label.stringValue = L("shortcut.recording")
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            label.textColor = .labelColor
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            updateDisplay()
        }
        return accepted
    }

    func updateDisplay() {
        if window?.firstResponder === self {
            label.stringValue = L("shortcut.recording")
        } else {
            label.stringValue = spec.enabled ? spec.displayText : L("shortcut.disabled")
        }
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.textColor = spec.enabled ? .labelColor : .secondaryLabelColor
        needsLayout = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc — キャンセル（フォーカスを外すだけ）
            window?.makeFirstResponder(nil)
            return
        case 51, 117: // Delete / ForwardDelete — 無効化
            var updated = spec
            updated.enabled = false
            onChange(updated)
            window?.makeFirstResponder(nil)
            return
        default:
            break
        }

        // 修飾キー単独の押下は無視する
        let knownModifierCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if knownModifierCodes.contains(event.keyCode) { return }

        let modifiers = GlobalShortcutManager.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            // 修飾キー無しの素のキーは安全のため記録しない
            NSSound.beep()
            return
        }

        var updated = spec
        updated.keyCode = Int(event.keyCode)
        updated.modifiers = modifiers
        updated.enabled = true
        onChange(updated)
        window?.makeFirstResponder(nil)
    }

    /// 修飾キーの押下状態変化では何もしない（キー確定時にまとめて記録する）。
    override func flagsChanged(with event: NSEvent) {}
}
