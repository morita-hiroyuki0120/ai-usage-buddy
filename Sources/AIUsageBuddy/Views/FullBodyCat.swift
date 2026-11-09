import AppKit
import SwiftUI

struct FullBodyCat: View {
    let state: CharacterState
    var elapsed: Double? = nil

    private var color: NSColor {
        switch state {
        case .energetic: return .systemTeal
        case .normal: return .systemBlue
        case .tired: return .systemOrange
        case .sleeping, .unknown: return .systemGray
        }
    }

    var body: some View {
        Canvas { context, size in
            let width = min(size.width - 4, (size.height - 6) * 100 / 64)
            let height = width * 64 / 100
            context.withCGContext { cg in
                CatDrawing.draw(in: cg, rect: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                                    width: width, height: height),
                                state: state, elapsed: elapsed, color: color.cgColor, template: false)
            }
        }
        .accessibilityLabel(L(state.localizedNameKey))
    }
}
