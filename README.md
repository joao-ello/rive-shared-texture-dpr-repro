# rive-flutter 0.14.7 — shared-texture web misposition repro

A `RiveWidget(useSharedTexture: true)` rendered into a `RivePanel` is **mispositioned on
Flutter web** when both of these hold:

1. the `RiveWidget` is **offset within its `RivePanel`** (it does not fill the panel), and
2. an ancestor **`MediaQuery` overrides `devicePixelRatio`** to a value different from
   `window.devicePixelRatio`.

No ancestor transform is required. Correct on native (iOS/Android/desktop); was correct
before 0.14.7.

## Run

```sh
flutter pub get
flutter run -d chrome      # or: flutter run -d web-server --web-port 8765
```

Three panels (coyote should be centered in the blue square in all three):

| Panel | offset painter | MediaQuery dpr | result |
| -- | -- | -- | -- |
| **A** reference | yes | == window dpr | ✅ centered |
| **B** minimal bug | yes | window dpr × 1.4 | ❌ **offset** |
| **C** control | no (fills panel) | window dpr × 1.4 | ✅ centered |

`B` vs `A` isolates the dpr mismatch; `B` vs `C` shows a non-zero panel-relative offset
is required. The `×1.4` is a *relative* mismatch, so it reproduces at any
`window.devicePixelRatio` (retina or not).

## Cause

Introduced in **0.14.7** (commit `b2ce130`, "shared texture fixes and improvements").
`SharedTextureViewRenderObject.paintIntoSharedTexture` changed from absolute positioning

```dart
final globalPosition = localToGlobal(Offset.zero) - panelRenderBox.localToGlobal(Offset.zero);
renderer.transform(Mat2D.fromScaleAndTranslation(
    scaleWidth, scaleHeight, globalPosition.dx * devicePixelRatio, globalPosition.dy * devicePixelRatio));
```

to a relative painter→panel transform:

```dart
final m = getTransformTo(panelRenderBox).storage;
final dpr = devicePixelRatio; // == MediaQuery.devicePixelRatioOf(context)
renderer.transform(Mat2D.fromScaleAndTranslation(
    m[0].abs() * dpr, m[5].abs() * dpr, m[12] * dpr, m[13] * dpr));
```

The panel-relative translation `m[12]/m[13]` is multiplied by `MediaQuery.devicePixelRatioOf(context)`,
but the shared-texture canvas is sized by `window.devicePixelRatio` (in `rive_native`'s web
backend). When those diverge and the offset is non-zero, the artwork is drawn at
`offset × (mqDpr / windowDpr)` and lands off-position.

Real-world trigger: any app that overrides `MediaQuery.devicePixelRatio` — device-preview
shells, render-resolution scalers, etc. (e.g. a `FittedBox`-based device frame whose
`compensatedDpr = actualDpr / fittedScale` diverges from the window dpr whenever the window
is smaller than the framed content).

`rive: 0.14.7` · Flutter web.
