import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../fabric_painter.dart';
import '../physics.dart';

/// Lets you trigger the same actions as the "PULL THE PINS" / "RESET" buttons
/// from outside the widget.
class FabricController {
  _FabricEffectState? _state;

  /// The pins let go one by one and the sheet falls off the wall.
  void releasePins() => _state?._releasePins();

  /// Puts the real widget back (cloth is thrown away).
  void reset() => _state?._reset();

  /// True while the cloth (instead of the live widget) is on screen.
  bool get isActive => _state?._active ?? false;
}

class FabricEffect extends StatefulWidget {
  final Widget child;

  /// Shown behind the cloth once it is torn / released
  /// (e.g. "You pulled the screen off the wall.").
  final Widget? backdrop;

  final FabricController? controller;

  /// Nodes across. Rows are derived from the widget's aspect ratio unless
  /// [gridRows] is given.
  final int gridColumns;
  final int? gridRows;

  /// Size of the area your finger grabs, in logical pixels.
  final double grabRadius;

  /// How deep the finger pushes into the cloth, in logical pixels.
  final double pushDepth;

  /// Spring tears above this stretch (x rest length). Higher = harder to rip.
  final double tearRatio;

  /// Pin lets go above this stretch. Higher = harder to peel off the wall.
  final double pinBreakRatio;

  /// Use a long-press to start (recommended when [child] scrolls or has taps
  /// that must keep working with a normal drag).
  final bool startOnLongPress;

  final bool enabled;

  const FabricEffect({
    super.key,
    required this.child,
    this.backdrop,
    this.controller,
    this.gridColumns = 24,
    this.gridRows,
    this.grabRadius = 48.0,
    this.pushDepth = 40.0,
    this.tearRatio = 3.2,
    this.pinBreakRatio = 2.0,
    this.startOnLongPress = false,
    this.enabled = true,
  });

  @override
  State<FabricEffect> createState() => _FabricEffectState();
}

class _FabricEffectState extends State<FabricEffect>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  late final Ticker _ticker;
  ui.Image? _image;
  FabricSimulation? _simulation;
  double _pixelRatio = 1.0;

  bool _active = false; // cloth visible instead of the live child
  bool _starting = false; // capture in progress
  bool _pointerDown = false;
  Offset _pointer = Offset.zero;

  Duration _lastElapsed = Duration.zero;
  double _accumulator = 0.0;
  int _calmFrames = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(covariant FabricEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _ticker.stop();
    _ticker.dispose();
    _frame.dispose();
    _image?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ ticker

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastElapsed = Duration.zero;
    _accumulator = 0.0;
    _calmFrames = 0;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final FabricSimulation? sim = _simulation;
    if (sim == null) {
      _ticker.stop();
      return;
    }

    double dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt > 0.05) dt = 0.05;
    _accumulator += dt;

    int steps = 0;
    while (_accumulator >= FabricSimulation.timeStep && steps < 3) {
      sim.step();
      _accumulator -= FabricSimulation.timeStep;
      steps++;
    }
    if (steps == 3) _accumulator = 0.0; // never spiral behind

    if (steps > 0) _frame.value++; // repaint only, no rebuild

    _checkRest(sim);
  }

  void _checkRest(FabricSimulation sim) {
    if (_pointerDown && sim.isGrabbing) {
      _calmFrames = 0;
      return;
    }

    // Nothing torn and the sheet is flat again -> give the real widget back,
    // so buttons / scrolling work and no physics runs while idle.
    if (!sim.gravityOn && sim.maxOffset < 0.4 && sim.motion < 0.02) {
      _restoreLiveChild();
      return;
    }

    // Torn / released cloth that stopped moving -> stop the ticker, keep
    // showing the cloth until reset().
    if (sim.gravityOn && sim.motion < 0.01) {
      _calmFrames++;
      if (_calmFrames > 30) _ticker.stop();
    } else {
      _calmFrames = 0;
    }
  }

  // --------------------------------------------------------------- lifecycle

  Future<bool> _ensureSimulation() async {
    if (_simulation != null) return true;
    if (_starting) return false;
    _starting = true;
    try {
      final RenderObject? renderObject =
      _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        return false;
      }
      final double pixelRatio = View.of(context).devicePixelRatio;
      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      if (!mounted) {
        image.dispose();
        return false;
      }

      final Size size = renderObject.size;
      final int cols = math.max(4, widget.gridColumns);
      final double spacing = size.width / (cols - 1);
      final int rows = math.min(
        220,
        widget.gridRows ?? math.max(4, (size.height / spacing).round() + 1),
      );

      setState(() {
        _pixelRatio = pixelRatio;
        _image = image;
        _simulation = FabricSimulation(
          width: size.width,
          height: size.height,
          cols: cols,
          rows: rows,
          tearRatio: widget.tearRatio,
          pinBreakRatio: widget.pinBreakRatio,
        );
        _active = true;
      });
      _startTicker();
      return true;
    } catch (_) {
      return false; // e.g. boundary was still dirty - just try again on next touch
    } finally {
      _starting = false;
    }
  }

  void _restoreLiveChild() {
    _ticker.stop();
    _simulation?.endGrab();
    final ui.Image? oldImage = _image;
    _simulation = null;
    _image = null;
    if (mounted) {
      setState(() => _active = false);
    }
    if (oldImage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldImage.dispose());
    }
  }

  void _reset() => _restoreLiveChild();

  Future<void> _releasePins() async {
    if (!await _ensureSimulation()) return;
    _simulation?.releasePins();
    _startTicker();
  }

  // ------------------------------------------------------------------ touch

  void _onDown(Offset position) {
    if (!widget.enabled) return;
    _pointerDown = true;
    _pointer = position;

    if (_simulation == null) {
      _ensureSimulation().then((bool ok) {
        if (ok && _pointerDown) _grab();
      });
    } else {
      _grab();
    }
  }

  void _grab() {
    final FabricSimulation? sim = _simulation;
    if (sim == null) return;
    sim.beginGrab(
      _pointer.dx,
      _pointer.dy,
      radius: widget.grabRadius,
      pushDepth: widget.pushDepth,
    );
    _startTicker();
  }

  void _onMove(Offset position) {
    _pointer = position;
    _simulation?.moveGrab(position.dx, position.dy);
  }

  void _onUp() {
    _pointerDown = false;
    _simulation?.endGrab();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final bool longPress = widget.startOnLongPress;
    final FabricSimulation? sim = _simulation;
    final ui.Image? image = _image;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: longPress ? null : (d) => _onDown(d.localPosition),
      onPanUpdate: longPress ? null : (d) => _onMove(d.localPosition),
      onPanEnd: longPress ? null : (_) => _onUp(),
      onPanCancel: longPress ? null : _onUp,
      onLongPressStart: longPress ? (d) => _onDown(d.localPosition) : null,
      onLongPressMoveUpdate:
      longPress ? (d) => _onMove(d.localPosition) : null,
      onLongPressEnd: longPress ? (_) => _onUp() : null,
      onLongPressCancel: longPress ? _onUp : null,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (widget.backdrop != null)
            Positioned.fill(
              child: Offstage(offstage: !_active, child: widget.backdrop),
            ),
          // The real UI. It stays in the tree (needed for capture) but is
          // invisible and untouchable while the cloth is shown.
          IgnorePointer(
            ignoring: _active,
            child: Opacity(
              opacity: _active ? 0.0 : 1.0,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: widget.child,
              ),
            ),
          ),
          Positioned.fill(
            child: (_active && sim != null && image != null)
                ? IgnorePointer(
              child: CustomPaint(
                painter: FabricPainter(
                  sim,
                  image,
                  devicePixelRatio: _pixelRatio,
                  repaint: _frame,
                ),
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}