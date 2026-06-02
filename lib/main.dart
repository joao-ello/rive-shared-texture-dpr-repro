// Minimal repro: a shared-texture RiveWidget mispositions when (1) it is offset
// within its RivePanel (doesn't fill it) and (2) an ancestor MediaQuery overrides
// devicePixelRatio to a value different from the real view dpr. No ancestor
// transform needed. Reproduces on stock rive 0.14.6 and 0.14.7, web and native.
//
// The shared-texture painter scales its panel-relative offset by
// MediaQuery.devicePixelRatioOf(context), but the texture canvas is sized by the
// real view dpr (window.devicePixelRatio). When they diverge, an offset painter
// lands at offset * (mqDpr / realDpr). Sourcing the dpr from
// View.of(context).devicePixelRatio fixes it.
//
// Each cell: blue = RivePanel texture surface, red border = panel bounds; the
// coyote should be centered in blue.
//   A reference     offset painter, dpr matches window  -> correct
//   B minimal bug   offset painter, dpr = window x 1.4  -> MISPOSITIONED
//   C control       fills panel,    dpr = window x 1.4  -> correct (offset is 0)
// ignore_for_file: experimental_member_use
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RiveNative.init();
  runApp(const ReproApp());
}

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('rive shared-texture devicePixelRatio repro'),
        ),
        body: Center(
          child: Wrap(
            spacing: 48,
            runSpacing: 32,
            children: const [
              _Cell(label: 'A reference\noffset painter, dpr matches',
                  dprFactor: 1.0, fill: false),
              _Cell(label: 'B MINIMAL BUG\noffset painter, dpr x1.4',
                  dprFactor: 1.4, fill: false),
              _Cell(label: 'C control\nFILL painter, dpr x1.4',
                  dprFactor: 1.4, fill: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.dprFactor, required this.fill});
  final String label;
  final double dprFactor;
  final bool fill;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(devicePixelRatio: mq.devicePixelRatio * dprFactor),
              child: _Panel(fill: fill),
            );
          }),
        ],
      ),
    );
  }
}

class _Panel extends StatefulWidget {
  const _Panel({required this.fill});
  final bool fill;
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  late final FileLoader _loader =
      FileLoader.fromAsset('assets/repro.riv', riveFactory: Factory.rive);
  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = SizedBox(
      width: widget.fill ? 100 : 44,
      height: widget.fill ? 100 : 44,
      child: RiveWidgetBuilder(
        fileLoader: _loader,
        builder: (context, state) => switch (state) {
          RiveLoading() => const SizedBox.shrink(),
          RiveFailed() => const ColoredBox(color: Colors.orange),
          RiveLoaded() => RiveWidget(
              controller: state.controller,
              fit: Fit.contain,
              useSharedTexture: true, // draw into the nearest RivePanel
            ),
        },
      ),
    );
    return SizedBox(
      width: 100,
      height: 100,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: Colors.red, width: 2)),
        child: RivePanel(
          backgroundColor: const Color(0x3300AAFF),
          child: Align(alignment: Alignment.center, child: art),
        ),
      ),
    );
  }
}
