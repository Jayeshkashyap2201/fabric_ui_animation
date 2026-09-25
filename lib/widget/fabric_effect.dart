import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../fabric_painter.dart';
import '../physics.dart';

/// Optional callbacks so you can trigger your own sound effects (or haptics)
/// at the right moments. All are null (silent) by default - wire up
/// whichever ones you want, e.g. with `audioplayers` or `SystemSound.play`.
class FabricSounds {
  /// Called the moment a touch first grabs the cloth.
  final VoidCallback? onGrab;

  /// Called every time a spring tears (a hole/rip opens).
  final VoidCallback? onTear;

  /// Called every time a pin lets go of the wall.
  final VoidCallback? onPinBreak;

  /// Called once the cloth has fully stopped moving after being torn or
  /// released (good for a soft "thud" as it settles).
  final VoidCallback? onSettle;

  const FabricSounds({
    this.onGrab,
    this.onTear,
    this.onPinBreak,
    this.onSettle,
  });
}

/// Lets you trigger the same actions as buttons from outside the widget:
/// pull the pins (with speed control), drop every pin at once, shrink the
/// whole thing away, bring it back, or put the real widget back.
class FabricController {
  _FabricEffectState? _state;

  /// The pins let go one after another (a "peel off the wall" wave) and the
  /// sheet falls. [speed] controls how spread out that wave is - shorter
  /// duration = pins let go closer together = a snappier drop.
  /// Pass [simultaneous]: true (or call [dropAllPins]) to release every pin
  /// on the same frame instead of a wave.
  void releasePins({
    Duration speed = const Duration(milliseconds: 750),
    bool simultaneous = false,
  }) =>
      _state?._releasePins(speed: speed, simultaneous: simultaneous);

  /// Every pin lets go on the same frame - the whole sheet drops at once.
  /// [speed] only affects how quickly it's considered "released" for
  /// bookkeeping; the fall speed itself comes from `elasticity.gravity`.
  void dropAllPins({Duration speed = const Duration(milliseconds: 300)}) =>
      _state?._releasePins(speed: speed, simultaneous: true);

  /// Crushes the whole widget toward a point - like paper being crumpled
  /// into a ball - then leaves it there (pair with a fade via [collapse],
  /// or just call this and then [reset] once you're done showing it).
  /// Give the point either as [originKey] (crumples toward that widget's
  /// centre - handy: pass the GlobalKey of the button that triggered this)
  /// or [origin] (a raw screen/global position). If neither is given, it
  /// crumples toward its own centre. Keeps whatever tearing/dropped pins
  /// already happened. Await the result (or pass [onComplete]) to know
  /// when the crumple has finished playing out.
  Future<void> crumple({
    GlobalKey? originKey,
    Offset? origin,
    Duration duration = const Duration(milliseconds: 500),
    VoidCallback? onComplete,
  }) async {
    await _state?._crumple(
      originKey: originKey,
      origin: origin,
      duration: duration,
    );
    onComplete?.call();
  }

  /// Puts the real widget back (cloth is thrown away) and shows it at full
  /// size again (undoes any [collapse]).
  void reset() => _state?._reset();

  /// Shrinks the whole widget down to nothing and fades it out - a quick
  /// "close" / "dismiss" animation independent of the cloth physics.
  /// [duration] is the speed of the animation. Call [expand] or [reset] to
  /// bring it back. Await the returned future to know when it's finished
  /// (e.g. to then pop a route or swap content), or pass [onComplete].
  Future<void> collapse({
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeInCubic,
    VoidCallback? onComplete,
  }) async {
    await _state?._collapse(duration: duration, curve: curve);
    onComplete?.call();
  }

  /// Reverse of [collapse]: grows back from nothing to full size and fades
  /// in. Useful when returning to a screen you previously [collapse]d.
  Future<void> expand({
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeOutCubic,
    VoidCallback? onComplete,
  }) async {
    await _state?._expand(duration: duration, curve: curve);
    onComplete?.call();
  }

  /// Snaps back to fully shown with no animation (e.g. before reusing the
  /// widget after a [collapse]).
  void resetTransition() => _state?._resetTransition();

  /// True while the cloth (instead of the live widget) is on screen.
  bool get isActive => _state?._active ?? false;
}

class FabricEffect extends StatefulWidget {
  final Widget child;

  /// Shown behind the cloth once it is torn / released
  /// (e.g. "You pulled the screen off the wall.").
  final Widget? backdrop;

  final FabricController? controller;

  /// Stretchiness / stiffness / damping. Defaults to [FabricElasticity.standard].
  /// Try [FabricElasticity.soft] or [FabricElasticity.stiff] for a different
  /// feel, or build a custom one.
  final FabricElasticity elasticity;

  /// Shadow/highlight colors for the fold lighting. Defaults to
  /// [FabricTheme.dark]; use [FabricTheme.light] (or
  /// `FabricTheme.forBrightness(Theme.of(context).brightness)`) for
  /// light-themed screens.
  final FabricTheme theme;

  /// Optional sound-effect hooks (grab / tear / pin-break / settle). Silent
  /// by default.
  final FabricSounds? sounds;

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
    this.elasticity = const FabricElasticity(),
    this.theme = const FabricTheme(),
    this.sounds,
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
    with TickerProviderStateMixin {
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

  /// Drives the shrink-to-vanish / grow-back animation. 1.0 = full size and
  /// opaque (normal), 0.0 = fully collapsed and invisible.
  late final AnimationController _transitionController = AnimationController(
    vsync: this,
    value: 1.0,
    duration: const Duration(milliseconds: 420),
  );

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
    _transitionController.dispose();
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
      if (_calmFrames > 30) {
        _ticker.stop();
        widget.sounds?.onSettle?.call();
      }
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
          elasticity: widget.elasticity,
        )
          ..onTear = widget.sounds?.onTear
          ..onPinBreak = widget.sounds?.onPinBreak;
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

  void _reset() {
    _restoreLiveChild();
    _transitionController.value = 1.0;
  }

  Future<void> _releasePins({
    required Duration speed,
    required bool simultaneous,
  }) async {
    if (!await _ensureSimulation()) return;
    // ~60 steps/sec: turn the requested speed into how spread out the pin
    // release wave is. 0 duration (or simultaneous) drops every pin at once.
    final int spreadFrames = simultaneous
        ? 0
        : (speed.inMilliseconds / (1000 / 60)).round().clamp(0, 600);
    _simulation?.releasePins(spreadFrames: spreadFrames);
    _startTicker();
  }

  Future<void> _crumple({
    GlobalKey? originKey,
    Offset? origin,
    required Duration duration,
  }) async {
    if (!await _ensureSimulation()) return;
    final RenderBox? boundaryBox =
    _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (boundaryBox == null || !boundaryBox.attached) return;

    Offset globalTarget;
    final RenderBox? keyBox =
    originKey?.currentContext?.findRenderObject() as RenderBox?;
    if (keyBox != null && keyBox.attached) {
      globalTarget = keyBox.localToGlobal(keyBox.size.center(Offset.zero));
    } else if (origin != null) {
      globalTarget = origin;
    } else {
      globalTarget = boundaryBox.localToGlobal(boundaryBox.size.center(Offset.zero));
    }

    final Offset local = boundaryBox.globalToLocal(globalTarget);
    _simulation?.beginCrumple(local.dx, local.dy);
    _startTicker();

    // Crossfade to nothing during the tail end, so it visually balls up
    // and vanishes together rather than lingering as a tiny flat wad.
    final Duration fade =
    Duration(milliseconds: (duration.inMilliseconds * 0.55).round());
    final Duration holdBeforeFade = duration - fade;
    if (holdBeforeFade > Duration.zero) {
      await Future<void>.delayed(holdBeforeFade);
    }
    if (!mounted) return;
    _transitionController.duration =
    fade > Duration.zero ? fade : const Duration(milliseconds: 1);
    await _transitionController.animateTo(0.0, curve: Curves.easeIn);
  }

  // --------------------------------------------------------- shrink/vanish

  Future<void> _collapse({
    required Duration duration,
    required Curve curve,
  }) async {
    _transitionController.duration = duration;
    await _transitionController.animateTo(0.0, curve: curve);
  }

  Future<void> _expand({
    required Duration duration,
    required Curve curve,
  }) async {
    _transitionController.duration = duration;
    await _transitionController.animateTo(1.0, curve: curve);
  }

  void _resetTransition() => _transitionController.value = 1.0;

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
    final bool grabbed = sim.beginGrab(
      _pointer.dx,
      _pointer.dy,
      radius: widget.grabRadius,
      pushDepth: widget.pushDepth,
    );
    if (grabbed) widget.sounds?.onGrab?.call();
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

    final Widget content = GestureDetector(
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
                  theme: widget.theme,
                  repaint: _frame,
                ),
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );

    // Shrink-to-vanish overlay. Cheap to keep in the tree: at value == 1.0
    // (the default, untouched state) this is a plain, unscaled, fully
    // opaque passthrough.
    return AnimatedBuilder(
      animation: _transitionController,
      builder: (BuildContext context, Widget? child) {
        final double t = _transitionController.value;
        if (t >= 1.0) return child!;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: t, child: child),
        );
      },
      child: content,
    );
  }
}