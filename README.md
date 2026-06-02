# rive-flutter — shared-texture RiveWidget mispositioned under a MediaQuery devicePixelRatio override

A `RiveWidget(useSharedTexture: true)` rendered into a `RivePanel` is **mispositioned** when:

1. the `RiveWidget` is **offset within its `RivePanel`** (it doesn't fill the panel), and
2. an ancestor **`MediaQuery` overrides `devicePixelRatio`** to a value different from the real
   view dpr (`window.devicePixelRatio`).

Reproduces on **web and native**, and on **stock rive `0.14.6` and `0.14.7`** — a long-standing
issue in the shared-texture path, not specific to a recent release. No ancestor transform needed.

Common in real apps: device-preview/inspector shells and "UI scaler" widgets routinely wrap the
app in `MediaQuery(devicePixelRatio: realDpr / scale)` so logical layout renders at a virtual
size. Any shared-texture `RiveWidget` under such a scaler mispositions.

![On `main` (stock rive 0.14.7), panel **B** is mispositioned (the coyote sits below-right of its red box); **A** and **C** are correct.](bug-screenshot.png)

## Branches

| Branch | rive | Result |
| -- | -- | -- |
| **`main`** | stock `^0.14.7` | reproduces the bug (panel **B** mispositioned) — `bug-screenshot.png` |
| **`fix`** | [`joao-ello/rive-flutter@shared-texture-dpr-fix`](https://github.com/joao-ello/rive-flutter/compare/master...shared-texture-dpr-fix) (0.14.7 + the dpr-source fix) | all panels correct — `fix-screenshot.png` |

The `fix` branch overrides `rive` to a fork of upstream `0.14.7` carrying only the suggested
fix, so you can see the before/after with the same app code.

## Run

```sh
flutter pub get
flutter run -d chrome      # or: flutter run -d web-server --web-port 8765
```

Three panels (coyote should be centered in the blue square in all three):

| Panel | offset painter | MediaQuery dpr | result (`main`) |
| -- | -- | -- | -- |
| **A** reference | yes | == window dpr | ✅ centered |
| **B** minimal bug | yes | window dpr × 1.4 | ❌ **offset** |
| **C** control | no (fills panel) | window dpr × 1.4 | ✅ centered |

`B` vs `A` isolates the dpr mismatch; `B` vs `C` shows a non-zero panel-relative offset is
required. The `×1.4` is a *relative* mismatch, so it reproduces at any `window.devicePixelRatio`
(retina or not).

## Cause

`SharedTextureViewRenderObject.paintIntoSharedTexture` multiplies its panel-relative transform by
`devicePixelRatio`, sourced from `MediaQuery.devicePixelRatioOf(context)`:

```dart
// SharedTextureView.build() passes MediaQuery.devicePixelRatioOf(context) as devicePixelRatio.
final m = getTransformTo(panelRenderBox).storage;   // 0.14.7 (0.14.6: localToGlobal diff)
final dpr = devicePixelRatio;                        // == MediaQuery.devicePixelRatioOf(context)
renderer.transform(Mat2D.fromScaleAndTranslation(
    m[0].abs() * dpr, m[5].abs() * dpr, m[12] * dpr, m[13] * dpr));
```

But the shared-texture canvas is sized by the **real** view dpr (`window.devicePixelRatio`), not
the overridable `MediaQuery` value. When an app overrides `MediaQuery.devicePixelRatio`, the two
diverge and a non-zero panel-relative offset is drawn at `offset × (mqDpr / realDpr)` → off-position.
The same `MediaQuery`-sourced dpr is used in `rive_panel.dart` (`RiveSurface.build`).

The 0.14.7 "shared texture fixes" rewrite (absolute `localToGlobal` → relative `getTransformTo`,
plus moving dpr into the scale term) changed how visibly this surfaces under ancestor transforms,
but the `MediaQuery`-vs-real-dpr divergence is present in 0.14.6 as well.

## Fix

Source the dpr from the real view, not the overridable MediaQuery (see the `fix` branch /
[fork diff](https://github.com/joao-ello/rive-flutter/compare/master...shared-texture-dpr-fix)):

```dart
// shared_texture_view.dart (SharedTextureView.build) and rive_panel.dart (RiveSurface.build):
- MediaQuery.devicePixelRatioOf(context)
+ View.of(context).devicePixelRatio
```

`View.of(context).devicePixelRatio` is the real, non-overridable view dpr, which matches the canvas
sizing, and keeps the relative `getTransformTo` transform intact. A `MediaQuery.devicePixelRatioOf`
dependency is retained so a runtime dpr change (e.g. dragging the window to a different-DPI monitor)
still triggers a rebuild.

![On the `fix` branch (rive 0.14.7 + the fix), all three panels render correctly — **B** is centered in its box.](fix-screenshot.png)

See [`UPSTREAM_ISSUE.md`](UPSTREAM_ISSUE.md) for the full writeup.
