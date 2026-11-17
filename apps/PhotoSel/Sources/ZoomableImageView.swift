import SwiftUI
import UIKit

/// Zoom shared by the panes of the compare view: zoom relative to "fit"
/// and normalised centre of the visible area (0...1 on both axes).
final class ZoomSync {
    struct State: Equatable {
        var relZoom: CGFloat
        var center: CGPoint
    }

    private var observers: [ObjectIdentifier: (State) -> Void] = [:]
    private(set) var last: State?

    func register(_ owner: AnyObject, apply: @escaping (State) -> Void) {
        observers[ObjectIdentifier(owner)] = apply
    }

    func unregister(_ owner: AnyObject) {
        observers[ObjectIdentifier(owner)] = nil
    }

    func publish(_ state: State, from owner: AnyObject) {
        last = state
        let me = ObjectIdentifier(owner)
        for (id, apply) in observers where id != me { apply(state) }
    }
}

/// Photo viewer: pinch to zoom, double tap fit ↔ 100%, swipe to change photo
/// when not zoomed, single tap for "only the photo".
struct ZoomableImageView: UIViewRepresentable {
    var image: UIImage?
    /// When it changes the view goes back to "fit" (new photo or rotation).
    var identity: Int
    var background: UIColor
    var zoomRequest: ZoomRequest?
    var sync: ZoomSync?
    var swipeEnabled = true
    var onSwipe: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?
    var onZoomedIn: ((Bool) -> Void)?

    func makeUIView(context: Context) -> ZoomScrollView {
        let v = ZoomScrollView()
        v.lastZoomRequestID = zoomRequest?.id ?? 0
        return v
    }

    func updateUIView(_ v: ZoomScrollView, context: Context) {
        v.onSwipe = onSwipe
        v.onSingleTap = onSingleTap
        v.onZoomedIn = onZoomedIn
        v.swipeEnabled = swipeEnabled
        v.backgroundColor = background
        v.setSync(sync)
        v.setImage(image, identity: identity)
        if let r = zoomRequest, r.id != v.lastZoomRequestID {
            v.lastZoomRequestID = r.id
            v.perform(r.command)
        }
    }

    static func dismantleUIView(_ v: ZoomScrollView, coordinator: ()) {
        v.setSync(nil)
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    var onSwipe: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?
    var onZoomedIn: ((Bool) -> Void)?
    var swipeEnabled = true
    var lastZoomRequestID = 0

    private var identity: Int?
    private var imageSize: CGSize = .zero
    private var fitScale: CGFloat = 1
    private var lastBounds: CGSize = .zero
    private var quiet = false          // programmatic change: do not publish
    private var zoomedIn = false
    private weak var sync: ZoomSync?

    init() {
        super.init(frame: .zero)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true
        imageView.layer.minificationFilter = .trilinear
        addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        single.require(toFail: double)
        addGestureRecognizer(single)
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            addGestureRecognizer(swipe)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Image

    func setSync(_ newSync: ZoomSync?) {
        guard newSync !== sync else { return }
        sync?.unregister(self)
        sync = newSync
        newSync?.register(self) { [weak self] state in self?.apply(state, quietly: true) }
    }

    func setImage(_ image: UIImage?, identity newIdentity: Int) {
        let same = image?.cgImage === imageView.image?.cgImage
            && image?.imageOrientation == imageView.image?.imageOrientation
        if newIdentity != identity {
            identity = newIdentity
            imageView.image = image
            configure(preserving: nil)
        } else if !same {
            let state = currentState()
            imageView.image = image
            configure(preserving: state)
        }
    }

    private func configure(preserving state: ZoomSync.State?) {
        quiet = true
        defer { quiet = false }
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageSize = .zero
            zoomScale = 1
            imageView.frame = .zero
            contentSize = .zero
            return
        }
        imageSize = image.size
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        contentSize = imageSize
        updateScales()
        if let state, state.relZoom > 1.001 {
            apply(state, quietly: true)
        } else if state == nil, let shared = sync?.last, shared.relZoom > 1.001 {
            apply(shared, quietly: true)       // compare: a new pane joins at the shared zoom
        } else {
            zoomScale = fitScale
            centerContent(resetOffset: true)
        }
        reportZoom()
    }

    private var actualSizeScale: CGFloat {
        1 / (window?.screen.scale ?? traitCollection.displayScale)
    }

    private func updateScales() {
        guard imageSize.width > 0, bounds.width > 0, bounds.height > 0 else { return }
        fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        minimumZoomScale = fitScale
        maximumZoomScale = max(fitScale * 4, actualSizeScale * 3)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBounds else { return }
        let state = imageSize == .zero || lastBounds == .zero ? nil : currentState()
        lastBounds = bounds.size
        quiet = true
        updateScales()
        if let state, state.relZoom > 1.001 {
            apply(state, quietly: true)
        } else if imageSize != .zero {
            zoomScale = fitScale
            centerContent(resetOffset: true)
        }
        quiet = false
    }

    // MARK: - Geometry

    private func centerContent(resetOffset: Bool = false) {
        let w = imageSize.width * zoomScale
        let h = imageSize.height * zoomScale
        let x = max(0, (bounds.width - w) / 2)
        let y = max(0, (bounds.height - h) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if resetOffset { contentOffset = CGPoint(x: -x, y: -y) }
    }

    private func currentState() -> ZoomSync.State {
        guard imageSize.width > 0, zoomScale > 0, fitScale > 0 else { return .init(relZoom: 1, center: CGPoint(x: 0.5, y: 0.5)) }
        let cx = (contentOffset.x + bounds.width / 2) / zoomScale / imageSize.width
        let cy = (contentOffset.y + bounds.height / 2) / zoomScale / imageSize.height
        return .init(relZoom: zoomScale / fitScale,
                     center: CGPoint(x: min(max(cx, 0), 1), y: min(max(cy, 0), 1)))
    }

    private func apply(_ state: ZoomSync.State, quietly: Bool) {
        guard imageSize.width > 0, fitScale > 0 else { return }
        let wasQuiet = quiet
        quiet = quiet || quietly
        defer { quiet = wasQuiet }
        zoomScale = min(max(state.relZoom * fitScale, minimumZoomScale), maximumZoomScale)
        centerContent()
        let w = imageSize.width * zoomScale, h = imageSize.height * zoomScale
        var off = CGPoint(x: state.center.x * w - bounds.width / 2, y: state.center.y * h - bounds.height / 2)
        off.x = min(max(off.x, -contentInset.left), max(-contentInset.left, w - bounds.width + contentInset.right))
        off.y = min(max(off.y, -contentInset.top), max(-contentInset.top, h - bounds.height + contentInset.bottom))
        contentOffset = off
        reportZoom()
    }

    private func reportZoom() {
        let z = imageSize != .zero && zoomScale > fitScale * 1.05
        if z != zoomedIn {
            zoomedIn = z
            let callback = onZoomedIn
            DispatchQueue.main.async { callback?(z) }
        }
    }

    private func publish() {
        guard !quiet, imageSize != .zero, let sync else { return }
        sync.publish(currentState(), from: self)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        reportZoom()
        publish()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        publish()
    }

    // MARK: - Gestures and commands

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        toggleZoom(at: g.location(in: imageView))
    }

    @objc private func singleTapped() { onSingleTap?() }

    @objc private func swiped(_ g: UISwipeGestureRecognizer) {
        guard swipeEnabled, imageSize != .zero, zoomScale <= fitScale * 1.01 else { return }
        onSwipe?(g.direction == .left ? 1 : -1)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Fit ↔ 100% (image pixel = screen pixel); if 100% is not bigger than fit, 2.5×.
    private func toggleZoom(at point: CGPoint?) {
        guard imageSize != .zero else { return }
        if zoomScale > fitScale * 1.01 {
            setZoomScale(fitScale, animated: true)
            return
        }
        let actual = actualSizeScale
        let target = min(actual > fitScale * 1.2 ? actual : fitScale * 2.5, maximumZoomScale)
        let p = point ?? CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    func perform(_ command: ZoomCommand) {
        guard imageSize != .zero else { return }
        switch command {
        case .toggle:
            toggleZoom(at: nil)
        case .zoomIn, .zoomOut:
            var state = currentState()
            state.relZoom *= command == .zoomIn ? 1.25 : 0.8
            UIView.animate(withDuration: 0.15) { self.apply(state, quietly: false) }
            publish()
        }
    }
}
