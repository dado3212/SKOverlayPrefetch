# <img src="/Demo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png?raw=true" height="32px" alt=""/> SKOverlayPrefetch

Prefetch `SKOverlay` so `present(in:)` shows up near-instantly instead of after a multi-second network load.

<table>
  <tr>
    <th>Normal</th>
    <th>Prefetched</th>
  </tr>
  <tr>
    <td>https://github.com/user-attachments/assets/c3d14720-930f-47cb-be8f-7c50396ba4c6</td>
    <td>https://github.com/user-attachments/assets/b705d9d7-f335-4b58-8eb6-45b23163e194</td>
  </tr>
  <tr>
    <td align="center">8,688 ms</td>
    <td align="center">25 ms</td>
  </tr>
</table>

Full write-up: [Speeding up SKOverlay with private APIs](https://blog.alexbeals.com/posts/speeding-up-skoverlay-with-private-apis).

## The problem

```swift
guard let scene = view.window?.windowScene else { return }

let config = SKOverlay.AppConfiguration(
    appIdentifier: "329218549",
    position: .bottom
)
let overlay = SKOverlay(configuration: config)
overlay.present(in: scene)
```

`SKOverlay` has to do a network request to turn the numerical ID like `329218549` into what shows up. That all happens in a network request after `present(in:)`, which can mean multiple-second delays between presenting the overlay and it actually showing up.

## How it works

`present(in:)` is `-[SKOverlay presentInScene:]`, which calls `[[scene _aso_appOverlayManager] presentOverlay:self]`. That launches `AppStoreOverlaysService`, an extension that hosts the overlay. The service asks a launchd daemon, `appstorecomponentsd`, for the app's info, and caches the result in memory.

Callers to the daemon are locked down, but the service caches the result, so if it has fetched once, the next present is nearly instant.

We can 'prefetch' by presenting once, invisibly: `_aso_appOverlayManager` (private) gives us the overlay's window, which we set to `alpha = 0` so the user can't see it and `isUserInteractionEnabled = false` so they can't touch it. Once it finishes presenting (`storeOverlayDidFinishPresentation`) we dismiss it and restore the window. The real present then hits the cache, happening immediately.

## Install

Copy `SKOverlayPrefetch/SKOverlayPrefetch.swift` into your target, or add this repo with Swift Package Manager and `import SKOverlayPrefetch`. iOS 14+.

## Usage

```swift
// When the scene becomes active (the cache is dropped in the background):
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

- **This isn't allowed by Apple.** App Store Review Guideline 2.5.1: "Apps may only use public APIs and must run on the currently shipping OS." The private API (`-[UIWindowScene _aso_appOverlayManager]` and the manager's `window`) is guarded with `responds(to:)`, so if it disappears the prefetch fails and `SKOverlay` works as normal. I haven't submitted an app using this.
- **The cache only lives while the app is visible.** Backgrounding shuts the service down and the prefetch is thrown away, so prefetch on each foreground.
- **The service rate-limits presents:** up to 5 at once, then 1 per second. A prefetch counts as one. Going over fails immediately (`SKErrorDomain` 0).
- **The icon may still be loading.** The prefetch finishes once the name, subtitle and price come back; the icon can take longer. Present too soon after prefetching and you'll briefly see a placeholder (visible in the prefetched video above).
- **Quick relaunches are slow.** launchd waits 10 s between launches of the daemon, so presenting, closing the app and reopening it can add up to ~10 s.
- A prefetch dismisses any overlay already on screen.
- Checked against iOS 14.5, 15.5 and 17.4 binaries and iOS 18.7 on device. May break in future iOS versions.

## Demo

`Demo/SKOverlayPrefetchDemo.xcodeproj` (iOS 14+): Prefetch, Present and Dismiss buttons with timings. Set your signing team to run on a device.
