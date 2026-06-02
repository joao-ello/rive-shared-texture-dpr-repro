<!-- Issue title -->
# Shared-texture RiveWidget mispositioned when an ancestor MediaQuery overrides devicePixelRatio

<!-- Body — matches rive-app/rive-flutter runtime-issue-template.yml (fill each field with the matching section) -->

### Submission checklist

- [x] I have confirmed the issue is present in the latest version of the `rive` Flutter package
- [x] I have searched the documentation and forums and could not find an answer
- [x] I have searched existing issues and this is not a duplicate

### Description

A `RiveWidget(useSharedTexture: true)` rendered into a `RivePanel` is drawn at the **wrong position** when both of these hold:

1. the `RiveWidget` is **offset within its `RivePanel`** (it does not fill the panel), and
2. an ancestor **`MediaQuery` overrides `devicePixelRatio`** to a value different from the real view dpr (`window.devicePixelRatio`).

**Expected:** the artwork renders centered in its panel (as it does when the painter fills the panel, or when the `MediaQuery` dpr matches the view dpr).
**Actual:** the artwork is offset by a factor of `mqDpr / realDpr`.

No ancestor transform is required. This is common in real apps: device-preview/inspector shells and "UI scaler" widgets routinely wrap the app in `MediaQuery(devicePixelRatio: realDpr / scale)` so logical layout renders at a virtual size — any shared-texture `RiveWidget` under such a scaler mispositions.

**Cause:** `SharedTextureViewRenderObject.paintIntoSharedTexture` scales its panel-relative transform by `devicePixelRatio`, which `SharedTextureView.build()` sources from `MediaQuery.devicePixelRatioOf(context)`. The shared-texture canvas, however, is sized by the **real** view dpr (`window.devicePixelRatio`). When an app overrides `MediaQuery.devicePixelRatio`, the two diverge and a non-zero panel-relative offset is scaled by `mqDpr / realDpr`. The same `MediaQuery`-sourced dpr is used in `rive_panel.dart` (`RiveSurface.build` → `SharedRenderTexture.devicePixelRatio`).

### Reproduction steps / code

Minimal repro repo (3 panels; the coyote should be centered in all three): **https://github.com/joao-ello/rive-shared-texture-dpr-repro**

- `main` branch = stock `rive` → panel **B** is mispositioned.
- `fix` branch = the suggested fix → all panels correct.

The essence:

```dart
MediaQuery(
  data: MediaQuery.of(context).copyWith(
    devicePixelRatio: MediaQuery.of(context).devicePixelRatio * 1.4, // mismatch vs real dpr
  ),
  child: SizedBox(
    width: 100, height: 100,
    child: DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Colors.red)),
      child: RivePanel(
        backgroundColor: const Color(0x3300AAFF),
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 44, height: 44, // smaller than the panel -> offset painter
            child: RiveWidgetBuilder(
              fileLoader: fileLoader,
              builder: (context, state) => switch (state) {
                RiveLoaded() => RiveWidget(
                    controller: state.controller, fit: Fit.contain,
                    useSharedTexture: true),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ),
      ),
    ),
  ),
)
```

| Panel | painter | MediaQuery dpr | result |
| -- | -- | -- | -- |
| A | offset (44 in a 100 panel) | == real dpr | correct |
| B | offset | real dpr × 1.4 | **mispositioned** |
| C | fills panel | real dpr × 1.4 | correct (offset is 0) |

### Source `.riv` / `.rev` file

The repro uses your own example asset (`example/assets/coyote.riv`), bundled in the repro repo as `assets/repro.riv`. Any `.riv` works — the bug is positional.

### Screenshots / video

Before/after are in the repo README: [`bug-screenshot.png`](https://github.com/joao-ello/rive-shared-texture-dpr-repro/blob/main/bug-screenshot.png) (B mispositioned) and [`fix-screenshot.png`](https://github.com/joao-ello/rive-shared-texture-dpr-repro/blob/main/fix-screenshot.png) (all correct).

### Rive Flutter package version

`0.14.7` (latest). Also reproduces on `0.14.6`, and on current `master` (`cc5147f`) — the dpr source there is still `MediaQuery.devicePixelRatioOf(context)`, even after the recent shared-texture transform reworks (#12675, #12688).

### Flutter version

```
Flutter 3.44.0 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 559ffa3f75 • 2026-05-15
Engine • hash fcf463a2242790d1fdcd9d044f533080f5022e18 (revision 4c525dac5e)
Tools • Dart 3.12.0 • DevTools 2.57.0
```

### Device

Web (Chrome, on a retina Mac) and iPad (iPadOS). Platform-agnostic — the `×1.4` is a *relative* mismatch, so it reproduces at any `window.devicePixelRatio`.

### OS version

macOS (web / Chrome, CanvasKit & skwasm) and iPadOS 17.

### Additional context

**Suggested fix** — source the dpr from the real view, not the overridable `MediaQuery`, in `shared_texture_view.dart` (`SharedTextureView.build`) and `rive_panel.dart` (`RiveSurface.build`):

```dart
- MediaQuery.devicePixelRatioOf(context)
+ View.of(context).devicePixelRatio
```

`View.of(context).devicePixelRatio` is the real, non-overridable view dpr, which matches the canvas sizing, and keeps the relative `getTransformTo` transform intact. (Retain a `MediaQuery.devicePixelRatioOf(context)` dependency so a runtime dpr change — e.g. moving the window to a different-DPI monitor — still triggers a rebuild, since `View.of` only notifies on view-identity changes.)

Full diff on a fork of current `master`: **https://github.com/joao-ello/rive-flutter/compare/master...shared-texture-dpr-fix** (verified — it makes panel B correct; this is what the repro's `fix` branch uses).

Happy to open a PR if that's a useful channel for you.
