import SwiftUI
import UIKit

/// A chart drag only wins after horizontal intent or a stationary long press.
/// Vertical movement fails early, letting the containing list continue the same touch.
struct AssetChartTouchSurface: UIViewRepresentable {
    var onInspect: (CGPoint) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> TouchView { TouchView() }

    func updateUIView(_ view: TouchView, context: Context) {
        view.recognizer.onInspect = onInspect
        view.recognizer.onEnd = onEnd
    }

    static func dismantleUIView(_ view: TouchView, coordinator: ()) {
        view.recognizer.isEnabled = false
    }

    final class TouchView: UIView {
        let recognizer = ChartRecognizer()
        private weak var parentScrollView: UIScrollView?

        init() {
            super.init(frame: .zero)
            backgroundColor = .clear
            addGestureRecognizer(recognizer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if parentScrollView !== scroll {
                        scroll.panGestureRecognizer.require(toFail: recognizer)
                        parentScrollView = scroll
                    }
                    break
                }
                ancestor = view.superview
            }
        }
    }

    final class ChartRecognizer: UIGestureRecognizer {
        var onInspect: (CGPoint) -> Void = { _ in }
        var onEnd: () -> Void = {}
        private var origin = CGPoint.zero
        private var latest = CGPoint.zero
        private var hold: Timer?
        private var inspecting = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard touches.count == 1, event.allTouches?.count == 1, let touch = touches.first else {
                let wasInspecting = inspecting
                finish()
                state = wasInspecting ? .cancelled : .failed
                return
            }
            origin = touch.location(in: view)
            latest = origin
            hold = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                guard let self, self.state == .possible else { return }
                self.beginInspection()
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else { return }
            latest = touch.location(in: view)
            if state == .possible {
                let dx = abs(latest.x - origin.x)
                let dy = abs(latest.y - origin.y)
                if dy >= 6, dy >= dx {
                    hold?.invalidate()
                    state = .failed
                } else if dx >= 8, dx > dy {
                    beginInspection()
                }
            } else if state == .began || state == .changed {
                state = .changed
                onInspect(latest)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            let wasInspecting = inspecting
            finish()
            state = wasInspecting ? .ended : .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            let wasInspecting = inspecting
            finish()
            state = wasInspecting ? .cancelled : .failed
        }

        override func reset() {
            finish()
            super.reset()
        }

        private func beginInspection() {
            hold?.invalidate()
            inspecting = true
            state = .began
            onInspect(latest)
        }

        private func finish() {
            hold?.invalidate()
            hold = nil
            if inspecting { onEnd() }
            inspecting = false
        }
    }
}
