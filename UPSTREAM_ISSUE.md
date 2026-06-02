<!-- Issue title -->
# Shared-texture RiveWidget mispositioned when an ancestor MediaQuery overrides devicePixelRatio

<!-- Body (matches rive-app/rive-flutter runtime-issue-template.yml) -->
# Title
Shared-texture RiveWidget mispositioned when an ancestor MediaQuery overrides devicePixelRatio

# Body

## Summary

A `RiveWidget(useSharedTexture: true)` rendered into a `RivePanel` is drawn at the **wrong position** when:

1. the `RiveWidget` is **offset within its `RivePanel`** (it doesn't fill the panel), and
2. an ancestor **`MediaQuery` overrides `devicePixelRatio`** to a value different from the real view dpr (`window.devicePixelRatio`).

Reproduces on **web and native**, and on both **0.14.6 and 0.14.7** (latest) — so it is a long-standing issue in the shared-texture path, not specific to a recent release. No ancestor transform is needed.

This is common in real apps: device-preview/inspector shells and "UI scaler" widgets routinely wrap the app in `MediaQuery(devicePixelRatio: realDpr / scale)` so logical layout renders at a virtual size. Any shared-texture `RiveWidget` under such a scaler mispositions.

## Cause

`SharedTextureViewRenderObject.paintIntoSharedTexture` computes the painter-to-panel transform and multiplies its translation by `devicePixelRatio`, sourced from `MediaQuery.devicePixelRatioOf(context)`:

```dart
// SharedTextureView.build() passes MediaQuery.devicePixelRatioOf(context) as devicePixelRatio.
final m = getTransformTo(panelRenderBox).storage;   // 0.14.7 (0.14.6: localToGlobal diff)
final dpr = devicePixelRatio;                        // == MediaQuery.devicePixelRatioOf(context)
renderer.transform(Mat2D.fromScaleAndTranslation(
    m[0].abs() * dpr, m[5].abs() * dpr, m[12] * dpr, m[13] * dpr));
```

But the shared-texture canvas is sized by the **real device pixel ratio** (`window.devicePixelRatio`), not the overridable `MediaQuery` value. When an app overrides `MediaQuery.devicePixelRatio`, the two diverge, and a non-zero panel-relative offset is scaled by `mqDpr / realDpr` → the artwork lands off-position. The same `MediaQuery`-sourced dpr is used in `rive_panel.dart` (`RiveSurface.build` → `SharedRenderTexture.devicePixelRatio`, used by `flush`).

(The 0.14.7 "shared texture fixes" rewrite — absolute `localToGlobal` → relative `getTransformTo`, plus moving dpr into the scale term — changed how visibly this surfaces under ancestor transforms, but the underlying `MediaQuery`-vs-real-dpr divergence is present in 0.14.6 as well.)

## Suggested fix

Source the dpr from the real view, not the overridable MediaQuery, in both places:

```dart
// shared_texture_view.dart (SharedTextureView.build) and
// rive_panel.dart (RiveSurface.build):
- MediaQuery.devicePixelRatioOf(context)
+ View.of(context).devicePixelRatio
```

`View.of(context).devicePixelRatio` is the real, non-overridable view dpr, which matches the canvas sizing. This keeps the relative `getTransformTo` transform intact.

## Minimal repro

Stock `rive` (tested on `0.14.6` and `0.14.7`), Flutter web or native. Full project attached/linked; `lib/main.dart` renders three panels (coyote should be centered in the blue panel in all three):

| panel | painter | MediaQuery dpr | result |
| -- | -- | -- | -- |
| A | offset (smaller, centered) | == real dpr | correct |
| B | offset | real dpr × 1.4 | **mispositioned** |
| C | fills panel | real dpr × 1.4 | correct (offset is 0) |

The core widget:

```dart
MediaQuery(
  data: MediaQuery.of(context).copyWith(
    devicePixelRatio: MediaQuery.of(context).devicePixelRatio * 1.4, // mismatch
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

Changing the dpr source to `View.of(context).devicePixelRatio` in the rive package fixes all cases.

Environment: rive 0.14.6 + 0.14.7, Flutter 3.x, web (CanvasKit/skwasm) and native iOS.
