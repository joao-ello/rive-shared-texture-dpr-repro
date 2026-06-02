# Shared-texture RiveWidget mispositioned when an ancestor MediaQuery overrides devicePixelRatio

**Tracking GitHub issue:** https://github.com/rive-app/rive-flutter/issues/640
**Minimal repro:** https://github.com/joao-ello/rive-shared-texture-dpr-repro

## What happens

A `RiveWidget(useSharedTexture: true)` rendered into a `RivePanel` is drawn at the **wrong position** when both of these are true:

1. the `RiveWidget` is **offset within its `RivePanel`** (it doesn't fill the panel), and
2. an ancestor **`MediaQuery` overrides `devicePixelRatio`** to a value different from the real view dpr (`window.devicePixelRatio`).

Expected: the artwork stays centered in its panel. Actual: it's shifted by a factor of `mqDpr / realDpr`. No ancestor transform is required, and it happens on **web and native**.

This is common in real apps — device-preview/inspector shells and "UI scaler" widgets routinely wrap the app in `MediaQuery(devicePixelRatio: realDpr / scale)` so the UI lays out at a virtual size. Any shared-texture `RiveWidget` under such a scaler mispositions.

## Versions

Reproduces on stock `rive` **0.14.6** and **0.14.7** (latest), and on current `master` (`cc5147f`). Flutter 3.44.0 / Dart 3.12.0. Web (Chrome, CanvasKit & skwasm) and iPad (iPadOS).

## Minimal repro

Three panels; the coyote should be centered in the blue square in all three:

| Panel | painter | MediaQuery dpr | result |
| -- | -- | -- | -- |
| A | offset (44 in a 100 panel) | == real dpr | correct |
| B | offset | real dpr × 1.4 | mispositioned |
| C | fills panel | real dpr × 1.4 | correct (offset is 0) |

`B` vs `A` isolates the dpr mismatch; `B` vs `C` shows a non-zero panel-relative offset is required. The `×1.4` is a relative mismatch, so it reproduces at any `window.devicePixelRatio`.

The core widget:

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

Full project (with before/after screenshots): https://github.com/joao-ello/rive-shared-texture-dpr-repro

## Cause

`SharedTextureViewRenderObject.paintIntoSharedTexture` scales its panel-relative transform by `devicePixelRatio`, which `SharedTextureView.build()` sources from `MediaQuery.devicePixelRatioOf(context)`. The shared-texture canvas, though, is sized by the **real** view dpr (`window.devicePixelRatio`). When an app overrides `MediaQuery.devicePixelRatio`, the two diverge and a non-zero panel-relative offset is scaled by `mqDpr / realDpr`. The same `MediaQuery`-sourced dpr is also used in `rive_panel.dart` (`RiveSurface.build`).

## Suggested fix

Source the dpr from the real view, not the overridable `MediaQuery`, in `shared_texture_view.dart` and `rive_panel.dart`:

```dart
- MediaQuery.devicePixelRatioOf(context)
+ View.of(context).devicePixelRatio
```

`View.of(context).devicePixelRatio` is the real, non-overridable view dpr, which matches the canvas sizing, and keeps the relative `getTransformTo` transform intact. (Retain a `MediaQuery.devicePixelRatioOf(context)` dependency so a runtime dpr change still triggers a rebuild, since `View.of` only notifies on view-identity changes.)

Verified diff on a fork of current master: https://github.com/joao-ello/rive-flutter/compare/master...shared-texture-dpr-fix
