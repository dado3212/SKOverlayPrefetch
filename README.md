# SKOverlayPrefetch

Proof of concept for making `SKOverlay` appear quickly by loading its pieces ahead of time.

A cold `SKOverlay.present(in:)` can take one to five seconds. Almost none of that is in your app:

1. **View service** – your app launches `AppStoreOverlaysService` (an extension) to host the overlay. About 150 ms.
2. **Daemon + data** – the service starts `appstorecomponentsd` only when it receives a presentation. The daemon boots (~0.4 s) and fetches the app's App Store "lockup". The service caches the result in memory.
3. **Presentation** – once the lockup is loaded, the overlay animates in.

If the daemon was started less than 10 seconds earlier (for example, you closed and reopened the app), launchd's default `ThrottleInterval` holds the new daemon back for the rest of those 10 seconds. The daemon exits as soon as its last client disconnects, so a quick relaunch hits this every time.

## Layout

```
SKOverlayPrefetch/
├── SKOverlayPrefetch/
│   └── SKOverlayPrefetch.swift   ← the whole library
├── Demo/                         ← proof-of-concept app
├── Package.swift
└── README.md
```

## Installation

Either:

- **Copy the file:** drag `SKOverlayPrefetch/SKOverlayPrefetch.swift` into your app target. It only uses UIKit and StoreKit, so there's nothing else to add, and no `import` is needed.
- **Swift Package Manager:** add this repository as a package dependency and `import SKOverlayPrefetch`.

Requires iOS 14+ (the same as `SKOverlay`). The demo app targets iOS 17.

## Usage

```swift
import SKOverlayPrefetch   // only when using the package

// When the scene becomes active (the service and daemon shut down in the background):
SKOverlayPrefetch.prefetch(appIdentifier: "361309726", in: windowScene) { failure in
    // nil on success
}

// Later, as usual:
overlay.present(in: windowScene)
```

| API | What it does |
|---|---|
| `prefetch(appIdentifier:in:completion:)` | Hidden present + dismiss: launches the service, starts the daemon, loads the lockup, leaves it in the service's cache. One at a time; a second call while one is running fails with `.busy`. |
| `isPrefetching` | True while a prefetch is running. |
| `present(_:in:)` | Likely not necessary. `SKOverlay.present(in:)`, deferred if a prefetch is still running so it doesn't go into the hidden window. |

`completion` gets `nil` on success, or a `Failure` for debugging: `.unavailable` (private API missing), `.busy`, `.timedOut`, or `.overlayFailed` with SKOverlay's error (e.g. `SKErrorDomain 20` if the scene isn't in the foreground).

## How the hidden prefetch works

- The overlay's window (owned by AppStoreOverlays' per-scene `ASOOverlayManager`) is only unhidden once the lockup has loaded. The prefetch sets that window to alpha 0 with touches off, presents, and dismisses from `storeOverlayDidFinishPresentation`.
- Dismissing any earlier reaches the service while the lockup is still loading and cancels the present (`SKErrorDomain` 15).
- Prefetch configurations carry no campaign or provider tokens.

## Caveats

- Uses private API (`-[UIWindowScene _aso_appOverlayManager]` and the manager's `window`). Both are guarded with `responds(to:)`; if they change, the prefetch fails with `.unavailable` and normal `SKOverlay` behaviour is unaffected. Not App Store safe.
- Doesn't check for an overlay already on screen: a prefetch while one is showing will dismiss it. Prefetch when the scene becomes active, before you present anything.
- Backgrounding the app shuts down the service and daemon and drops the cache. Prefetch again on each foreground.
- The service rate-limits presentations (`requestsPerSecond=1 timeWindow=5`, server-set). A real present immediately after a prefetch may be affected.
- Based on iOS 17.4 Simulator binaries and iOS 18.7 device logs.

## Demo

`Demo/SKOverlayPrefetchDemo.xcodeproj` is a small app with Prefetch, Present and Dismiss buttons and a log of timings (present → `storeOverlayWillStartPresentation`). Set your own signing team to run it on a device.
