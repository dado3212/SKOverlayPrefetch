# <img src="/Demo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png?raw=true" height="32px" alt=""/> SKOverlayPrefetch

Prefetch `SKOverlay` so `present(in:)` shows without the load delay (1–5 s when cold).

## Why it's slow

A cold present waits on:

1. **`AppStoreOverlaysService`** – the extension hosting the overlay (~150 ms to launch).
2. **`appstorecomponentsd`** – a daemon the service starts only on a presentation (~0.4 s to boot). It fetches the App Store lookup, which the service caches in memory.
3. **launchd** – if the daemon last started under 10 s ago (e.g. a quick relaunch), its default `ThrottleInterval` delays it for the rest of those 10 s.

## How it works

Presents a real overlay with its window hidden (alpha 0, no touches), dismisses it after `storeOverlayDidFinishPresentation`, then restores the window. Private API is only used to find that window. Dismissing earlier cancels the load (`SKErrorDomain` 15).

## Install

Copy `SKOverlayPrefetch/SKOverlayPrefetch.swift` into your target, or add this repo with Swift Package Manager and `import SKOverlayPrefetch`. iOS 14+.

## Usage

```swift
// When the scene becomes active (the service and daemon shut down in the background):
SKOverlayPrefetch.prefetch(appIdentifier: "361309726", in: scene) { failure in
    // nil on success
}

// Later, as usual:
overlay.present(in: scene)
```

- One prefetch at a time; `isPrefetching` is true while one runs.
- `present(_:in:)` waits for a running prefetch to finish. Likely unnecessary.
- `Failure`: `.unavailable` (private API missing), `.busy`, `.timedOut`, `.overlayFailed` (SKOverlay's error, e.g. `SKErrorDomain 20` when the scene isn't in the foreground).

## Caveats

- Private API (`-[UIWindowScene _aso_appOverlayManager]`, the manager's `window`), guarded with `responds(to:)`. If missing, prefetch fails and SKOverlay is unaffected. Not App Store safe; may break in future iOS versions.
- A prefetch dismisses any overlay already on screen.
- Backgrounding drops the cache. Prefetch on each foreground.
- The service rate-limits presentations (1 per second over 5 s, server-set).
- Checked against iOS 14.5, 15.5 and 17.4 binaries and iOS 18.7 on device.

## Demo

`Demo/SKOverlayPrefetchDemo.xcodeproj` (iOS 14+): Prefetch, Present and Dismiss buttons with timings. Set your signing team to run on a device.
