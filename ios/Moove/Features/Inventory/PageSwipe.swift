import SwiftUI
import UIKit

/// A horizontal page swipe for a view inside a vertical `ScrollView` that works wherever the finger
/// starts, item buttons included (Lisa's iPad: swiping on the shelf's items didn't turn the page).
///
/// A SwiftUI `DragGesture` there either loses to the buttons and the scroll view or blocks vertical
/// scrolling, so this puts a UIKit pan on the enclosing scroll view instead. It only begins when the
/// touch starts inside this view and moves mostly sideways; the scroll view's own pan waits for it
/// to fail, which it does at once on a vertical drag, so scrolling still works. Once it begins it
/// cancels the touch for the views under the finger, so a swipe never also taps an item; a tap or a
/// long press (no movement) never begins it, so buttons and context menus still work.
///
/// Put it in a `.background` outside any `.offset`, so its frame stays where the page sits.
struct HorizontalPageSwipe: UIViewRepresentable {
    /// The finger's horizontal travel since the swipe began, and this view's width.
    var onChanged: (_ dx: CGFloat, _ width: CGFloat) -> Void
    /// Where it ended, its horizontal velocity (pt/s) and this view's width. A cancelled swipe ends at 0.
    var onEnded: (_ dx: CGFloat, _ velocity: CGFloat, _ width: CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Marks the page's frame; re-attaches the pan when it moves into a window.
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPageSwipe
        private weak var anchor: UIView?
        private weak var host: UIView?
        private var pan: UIPanGestureRecognizer?

        init(_ parent: HorizontalPageSwipe) {
            self.parent = parent
        }

        /// Adds the pan to the nearest enclosing scroll view (else the window), once.
        func attach(to anchor: UIView) {
            self.anchor = anchor
            guard let window = anchor.window else {
                detach()
                return
            }
            var target: UIView = window
            var view = anchor.superview
            while let current = view {
                if current is UIScrollView {
                    target = current
                    break
                }
                view = current.superview
            }
            if host === target, pan != nil { return }
            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            target.addGestureRecognizer(pan)
            self.pan = pan
            host = target
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
            host = nil
        }

        @objc private func handle(_ gesture: UIPanGestureRecognizer) {
            guard let anchor else { return }
            let width = anchor.bounds.width
            switch gesture.state {
            case .changed:
                parent.onChanged(gesture.translation(in: anchor).x, width)
            case .ended:
                parent.onEnded(gesture.translation(in: anchor).x, gesture.velocity(in: anchor).x, width)
            case .cancelled, .failed:
                parent.onEnded(0, 0, width)
            default:
                break
            }
        }

        /// Only inside the page, and only when the drag is mostly horizontal.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan, gestureRecognizer === pan else { return true }
            guard let anchor, anchor.window != nil else { return false }
            let start = pan.location(in: anchor)
            guard anchor.bounds.insetBy(dx: 0, dy: -8).contains(start) else { return false }
            let t = pan.translation(in: anchor)
            let v = pan.velocity(in: anchor)
            let dx = abs(t.x) + abs(v.x) * 0.02
            let dy = abs(t.y) + abs(v.y) * 0.02
            return dx > dy * 1.3
        }

        /// The scroll view's pan waits for this one to fail, so a sideways swipe doesn't also
        /// nudge the page up or down.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, let scroll = host as? UIScrollView else { return false }
            return otherGestureRecognizer === scroll.panGestureRecognizer
        }
    }
}
