//
//  PrefetchDemo.swift
//
//  Runs SKOverlayPrefetch and times present(in:) → storeOverlayWillStartPresentation
//  (the moment the lockup has loaded and the overlay starts animating in).
//

import UIKit
import StoreKit
import SKOverlayPrefetch

@MainActor
final class PrefetchDemo: NSObject, ObservableObject {

    struct LogLine: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }

    @Published var appIdentifier = "361309726"      // Pages; any App Store ID works
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var isPrefetching = false

    private var overlay: SKOverlay?
    private var presentStart: CFAbsoluteTime = 0

    private var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    // 1. Service + daemon + lockup data (hidden present)
    func prefetch() {
        guard let scene, !isPrefetching else { return }
        isPrefetching = true
        let start = CFAbsoluteTimeGetCurrent()
        add("Prefetch started for \(appIdentifier)")
        SKOverlayPrefetch.prefetch(appIdentifier: appIdentifier, in: scene) { [weak self] failure in
            guard let self else { return }
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            add(failure.map { "Prefetch failed after \(ms) ms: \($0)" } ?? "Prefetch finished in \(ms) ms")
            isPrefetching = false
        }
    }

    // 2. Presentation
    func present() {
        guard let scene else { return }
        let config = SKOverlay.AppConfiguration(appIdentifier: appIdentifier, position: .bottom)
        config.userDismissible = true
        let overlay = SKOverlay(configuration: config)
        overlay.delegate = self
        self.overlay = overlay
        presentStart = CFAbsoluteTimeGetCurrent()
        add("Present \(appIdentifier)")
        SKOverlayPrefetch.present(overlay, in: scene)
    }

    func dismiss() {
        guard let scene else { return }
        SKOverlay.dismiss(in: scene)
    }

    func clearLog() { log.removeAll() }

    private func add(_ text: String) {
        log.append(LogLine(text: text))
    }
}

// SKOverlay calls its delegate on the main thread; hop onto the main actor with Sendable values.
extension PrefetchDemo: SKOverlayDelegate {
    nonisolated func storeOverlayWillStartPresentation(_ overlay: SKOverlay,
                                                       transitionContext: SKOverlay.TransitionContext) {
        let id = ObjectIdentifier(overlay)
        let now = CFAbsoluteTimeGetCurrent()
        Task { @MainActor [weak self] in
            guard let self, self.overlay.map(ObjectIdentifier.init) == id else { return }
            add("Visible after \(Int((now - presentStart) * 1000)) ms")
        }
    }

    nonisolated func storeOverlayDidFailToLoad(_ overlay: SKOverlay, error: Error) {
        let id = ObjectIdentifier(overlay)
        let nsError = error as NSError
        let message = "\(nsError.domain) \(nsError.code)"
        Task { @MainActor [weak self] in
            guard let self, self.overlay.map(ObjectIdentifier.init) == id else { return }
            add("Present failed: \(message)")
        }
    }
}
