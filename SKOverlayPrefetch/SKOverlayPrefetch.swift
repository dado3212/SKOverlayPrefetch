//
//  SKOverlayPrefetch.swift
//
//  Allows you to prefetch SKOverlay.present(in:) so that you can trigger it without delay.
//
//  Self-contained: copy this file into your target, or use it through the Swift package.
//
//  Works by triggering a fetch which populates the overlay cache. It uses private Apple 
//  APIs to get the overlay window, and hides it (isUserInteractionEnabled = false, 
//  alpha = 0) and tears it down after, remaining invisible to the end user while getting the
//  data into the cache.
//
//  This stops the user from absorbing the startup cost of AppStoreOverlaysService (~150ms) 
//  and appstorecomponentsd (a daemon the service starts only when it receives a presentation)
//  along with its App Store lookup, leading to immediate UI presentation.
//
//  The service and daemon shut down when your app goes to the background, so prefetch again
//  when the scene becomes active.
//
//  Uses PRIVATE API: `-[UIWindowScene _aso_appOverlayManager]` and the manager's `window`.
//  Both are guarded with responds(to:); if Apple changes them, prefetch fails with
//  `.unavailable` and plain SKOverlay keeps working. Works in iOS 14+ but may break with
//  future iOS versions. Not App Store safe.
//

import UIKit
import StoreKit

@MainActor
public final class SKOverlayPrefetch: NSObject {

    public enum Failure: Error, Equatable {
        /// A private API this relies on is missing (renamed or removed in this iOS version).
        case unavailable(String)
        /// Another prefetch is still running.
        case busy
        /// The overlay didn't finish presenting and dismissing within 15 s.
        case timedOut
        /// SKOverlay reported an error, e.g. "SKErrorDomain 20" when the scene isn't in the
        /// foreground, or "SKErrorDomain 15" when something dismissed it mid-load.
        case overlayFailed(String)
    }

    /// True while a prefetch is running.
    public static var isPrefetching: Bool { shared.active != nil }

    /// Hidden present + dismiss for `appIdentifier`: starts the overlay service and daemon,
    /// loads the lockup, and leaves it in the service's cache. `completion` gets nil on success.
    public static func prefetch(appIdentifier: String, in scene: UIWindowScene,
                                completion: ((Failure?) -> Void)? = nil) {
        shared.prefetch(appIdentifier: appIdentifier, in: scene, completion: completion)
    }

    /// Presents `overlay`, waiting for a running prefetch to finish first.
    ///
    /// Likely not necessary: once a prefetch has finished, plain `overlay.present(in:)` gets the
    /// same cached lockup. This only matters if you present while `isPrefetching` is true, when
    /// a plain present would go into the hidden window.
    public static func present(_ overlay: SKOverlay, in scene: UIWindowScene) {
        guard isPrefetching else { return overlay.present(in: scene) }
        shared.pendingPresent = { overlay.present(in: scene) }
    }

    // MARK: - Implementation

    private static let shared = SKOverlayPrefetch()
    private override init() { super.init() }

    private struct Active {
        let overlay: SKOverlay
        let scene: UIWindowScene
        let window: UIWindow
        let savedAlpha: CGFloat
        let savedInteraction: Bool
        let completion: ((Failure?) -> Void)?
        var timeout: Task<Void, Never>?
    }

    private var active: Active?
    private var pendingPresent: (() -> Void)?

    private func prefetch(appIdentifier: String, in scene: UIWindowScene,
                          completion: ((Failure?) -> Void)?) {
        guard active == nil else { completion?(.busy); return }

        // -[UIWindowScene(AppOverlayManager) _aso_appOverlayManager] → ASOOverlayManager.window
        let managerSelector = NSSelectorFromString("_aso_appOverlayManager")
        guard scene.responds(to: managerSelector),
              let manager = scene.perform(managerSelector)?.takeUnretainedValue() as? NSObject else {
            completion?(.unavailable("_aso_appOverlayManager")); return
        }
        guard manager.responds(to: NSSelectorFromString("window")),
              let window = manager.value(forKey: "window") as? UIWindow else {
            completion?(.unavailable("ASOOverlayManager.window")); return
        }

        let config = SKOverlay.AppConfiguration(appIdentifier: appIdentifier, position: .bottom)
        config.userDismissible = true          // no campaign/provider tokens: not an ad impression
        let overlay = SKOverlay(configuration: config)
        overlay.delegate = self

        let id = ObjectIdentifier(overlay)
        active = Active(overlay: overlay, scene: scene, window: window,
                        savedAlpha: window.alpha, savedInteraction: window.isUserInteractionEnabled,
                        completion: completion)
        active?.timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(id, failure: .timedOut)
        }

        // The manager only unhides this window once the lockup has loaded; at alpha 0 the
        // presentation runs but can't be seen or tapped.
        window.alpha = 0
        window.isUserInteractionEnabled = false
        overlay.present(in: scene)
        // Dismiss happens in storeOverlayDidFinishPresentation. Dismissing earlier reaches the
        // service mid-load and cancels the present (SKErrorDomain 15).
    }

    private func dismissIfActive(_ id: ObjectIdentifier) {
        guard let current = active, ObjectIdentifier(current.overlay) == id else { return }
        SKOverlay.dismiss(in: current.scene)
    }

    private func finish(_ id: ObjectIdentifier, failure: Failure?) {
        guard let current = active, ObjectIdentifier(current.overlay) == id else { return }
        current.timeout?.cancel()
        current.completion?(failure)
        // Restore after the manager has re-hidden the window, then run a deferred present.
        Task { @MainActor [self] in
            current.window.alpha = current.savedAlpha
            current.window.isUserInteractionEnabled = current.savedInteraction
            active = nil
            let present = pendingPresent
            pendingPresent = nil
            present?()
        }
    }
}

// SKOverlay calls its delegate on the main thread; each callback hops onto the main actor with
// only Sendable values (the overlay's identity and an error string).
extension SKOverlayPrefetch: SKOverlayDelegate {
    nonisolated public func storeOverlayDidFinishPresentation(_ overlay: SKOverlay,
                                                              transitionContext: SKOverlay.TransitionContext) {
        let id = ObjectIdentifier(overlay)
        Task { @MainActor in SKOverlayPrefetch.shared.dismissIfActive(id) }
    }

    nonisolated public func storeOverlayDidFinishDismissal(_ overlay: SKOverlay,
                                                           transitionContext: SKOverlay.TransitionContext) {
        let id = ObjectIdentifier(overlay)
        Task { @MainActor in SKOverlayPrefetch.shared.finish(id, failure: nil) }
    }

    nonisolated public func storeOverlayDidFailToLoad(_ overlay: SKOverlay, error: Error) {
        let id = ObjectIdentifier(overlay)
        let nsError = error as NSError
        let message = "\(nsError.domain) \(nsError.code)"
        Task { @MainActor in SKOverlayPrefetch.shared.finish(id, failure: .overlayFailed(message)) }
    }
}
