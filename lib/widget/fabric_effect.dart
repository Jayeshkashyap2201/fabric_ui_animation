import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'crumple.dart';
import 'fabric_elasticity.dart';
import '../fabric_painter.dart';
import '../physics.dart';
import 'pin_release.dart';
import 'fabric_sounds.dart';
import 'theme.dart';
import 'trigger.dart';

/// Lets you trigger the same actions as gestures/buttons from outside the
/// widget: pull the pins, drop every pin at once, crumple, shrink the whole
/// thing away, bring it back, or put the real widget back.
///
/// Every method that takes `options` uses the widget's own options
/// (`FabricEffect.crumple` / `FabricEffect.pins`) when you leave it out.
class FabricController {
  _FabricEffectState? _state;

  /// The pins let go one after another (a "peel off the wall" wave).
  Future<void> releasePins({PinOptions? options}) async {
    await _state?._releasePins(options: options);
  }

  /// Every pin lets go on the same frame - the whole sheet drops at once.
  Future<void> dropAllPins({PinOptions? options}) async {
    await _state?._releasePins(options: options, forceAll: true);
  }

  /// Crushes the widget toward a point like paper being crumpled into a
  /// ball, then fades it out. The point is [originKey]'s widget centre
  /// (pass the key of the button that triggered this), or [origin] (a
  /// global position); with neither it crumples toward its own centre.
  /// Keeps whatever tearing / dropped pins already happened.
  Future<void> crumple({
    CrumpleOptions? options,
    GlobalKey? originKey,
    Offset? origin,
  }) async {
    await _state?._crumple(
      options: options,
      originKey: originKey,
      origin: origin,
    );
  }

  /// Puts the real widget back (cloth thrown away) at full size.
  void reset() => _state?._reset();

  /// Shrinks the whole widget to nothing and fades it out.
  Future<void> collapse({
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeInCubic,
  }) async {
    await _state?._collapse(duration: duration, curve: curve);
  }

  /// Reverse of [collapse]: grows back to full size.
  Future<void> expand({
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeOutCubic,
  }) async {
    await _state?._expand(duration: duration, curve: curve);
  }

  /// Snaps back to fully shown, no animation.
  void resetTransition() => _state?._resetTransition();

  /// True while the cloth (instead of the live widget) is on screen.
  bool get isActive => _state?._active ?? false;
}

/// Wraps any widget so it behaves like a piece of cloth: grab, pull, stretch,
/// tear it - and, if you pass the matching options, crumple it or pull its
/// pins straight from a gesture, with no extra code.
class FabricEffect extends StatefulWidget {
  const FabricEffect({
    super.key,
    required this.child,
    this.backdrop,
    this.controller,
    this.elasticity = const FabricElasticity(),
    this.theme = const FabricTheme(),
    this.sounds,
    this.crumple,
    this.pins,
    this.gridColumns = 24,
    this.gridRows,
    this.grabRadius = 48.0,
    this.pushDepth = 40.0,
    this.tearRatio = 3.2,
    this.pinBreakRatio = 2.0,
    this.startOnLongPress = false,
    this.enabled = true,
  });

  final Widget child;

  /// Shown behind the cloth once it is torn / released.
  final Widget? backdrop;

  final FabricController? controller;

  /// Stretchiness / stiffness / damping. See [FabricElasticity.soft] and
  /// [FabricElasticity.stiff] for presets.
  final FabricElasticity elasticity;

  /// Shadow / highlight colours. Use [FabricTheme.light] on light screens.
  final FabricTheme theme;

  /// Sound / haptic hooks. Silent when null.
  final FabricSounds? sounds;

  /// Crumple settings. When given (and its `trigger` isn't `none`) the widget
  /// crumples toward the touch point on that gesture by itself.
  final CrumpleOptions? crumple;

  /// Pin-release settings. When given (and its `trigger` isn't `none`) the
  /// widget releases its pins on that gesture by itself.
  final PinOptions? pins;

  /// Nodes across. Rows follow the aspect ratio unless [gridRows] is set.
  final int gridColumns;
  final int? gridRows;

  /// Size of the area your finger grabs, in logical pixels.
  final double grabRadius;

  /// How deep the finger pushes into the cloth.
  final double pushDepth;

  /// A spring tears above this stretch (x rest length).
  final double tearRatio;

  /// A pin lets go above this stretch.
  final double pinBreakRatio;

  /// Start grabbing with a long-press instead of a plain drag (use when the
  /// child scrolls). A `crumple`/`pins` trigger set to `longPress` is
  /// ignored while this is true.
  final bool startOnLongPress;

  final bool enabled;

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
  Offset _lastDoubleTapPosition = Offset.zero;

  Duration _lastElapsed = Duration.zero;
  double _accumulator = 0.0;
  int _calmFrames = 0;
  final List<VoidCallback> _settleCallbacks = <VoidCallback>[];

  /// Drives collapse / expand / the crumple fade-out.
  /// 1.0 = full size and opaque (normal), 0.0 = gone.
  late final AnimationController _transitionController = AnimationController(
    vsync: this,
    value: 1.0,
    duration: const Duration(milliseconds: 420),
  );

  /// Where the shrink-to-vanish animation scales toward. Defaults to the
  /// widget's own centre; a crumple moves this to the point it was
  /// triggered from, so the vanish finishes exactly there instead of at
  /// the widget's centre.
  Alignment _transitionOrigin = Alignment.center;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller?._state = this;
    assert(() {
      final FabricTrigger c = widget.crumple?.trigger ?? FabricTrigger.none;
      final FabricTrigger p = widget.pins?.trigger ?? FabricTrigger.none;
      if (c != FabricTrigger.none && c == p) {
        throw FlutterError(
          'FabricEffect: crumple and pins are both set to trigger on $c. '
              'Give each a different trigger (or FabricTrigger.none).',
        );
      }
      return true;
    }());
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
        final List<VoidCallback> callbacks =
        List<VoidCallback>.of(_settleCallbacks);
        _settleCallbacks.clear();
        for (final VoidCallback callback in callbacks) {
          callback();
        }
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
      return false; // e.g. boundary was still dirty - just try again
    } finally {
      _starting = false;
    }
  }

  void _restoreLiveChild() {
    _ticker.stop();
    _simulation?.endGrab();
    _settleCallbacks.clear();
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
    _transitionOrigin = Alignment.center;
    _transitionController.value = 1.0;
  }

  /// Puts the widget back and grows it in again.
  Future<void> _autoReset(Duration? delay) async {
    if (delay == null) return;
    await Future<void>.delayed(delay);
    if (!mounted) return;
    _restoreLiveChild();
    _transitionOrigin = Alignment.center;
    _transitionController.value = 0.0;
    await _transitionController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // ----------------------------------------------------------------- pins

  Future<void> _releasePins({PinOptions? options, bool forceAll = false}) async {
    final PinOptions o = options ?? widget.pins ?? const PinOptions();
    if (!await _ensureSimulation()) return;
    final FabricSimulation? sim = _simulation;
    if (sim == null) return;

    final PinReleaseForce force =
    PinReleaseForce(options: o, forceAllAtOnce: forceAll);
    force.start(sim);
    sim.addForce(force);
    widget.sounds?.onPinsReleased?.call();
    _startTicker();

    _settleCallbacks.add(() {
      o.onComplete?.call();
      _autoReset(o.autoResetAfter);
    });
  }

  // -------------------------------------------------------------- crumple

  Future<void> _crumple({
    CrumpleOptions? options,
    GlobalKey? originKey,
    Offset? origin,
    Offset? localOrigin,
  }) async {
    final CrumpleOptions o = options ?? widget.crumple ?? const CrumpleOptions();
    if (!await _ensureSimulation()) return;
    final FabricSimulation? sim = _simulation;
    if (sim == null) return;

    Offset local;
    if (localOrigin != null) {
      // A gesture that landed on this widget - already in local space.
      local = localOrigin;
    } else {
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
        globalTarget =
            boundaryBox.localToGlobal(boundaryBox.size.center(Offset.zero));
      }
      local = boundaryBox.globalToLocal(globalTarget);
    }

    // The vanish animation scales toward this point instead of the
    // widget's centre, so it visually finishes right where it was
    // triggered from (e.g. the button that called it).
    _transitionOrigin = Alignment(
      (local.dx / sim.width) * 2 - 1,
      (local.dy / sim.height) * 2 - 1,
    );

    final CrumpleForce force = CrumpleForce(
      targetX: local.dx,
      targetY: local.dy,
      options: o,
    );
    force.start(sim);
    sim.addForce(force);
    widget.sounds?.onCrumple?.call();
    _startTicker();

    // Fade out during the tail end, so it balls up and vanishes together.
    final int totalMs = o.duration.inMilliseconds;
    final int fadeMs = (totalMs * o.fadeFraction.clamp(0.0, 1.0)).round();
    final int holdMs = totalMs - fadeMs;
    if (holdMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: holdMs));
    }
    // Someone reset / replaced the simulation meanwhile - stop here.
    if (!mounted || _simulation != sim) return;

    if (fadeMs > 0) {
      _transitionController.duration = Duration(milliseconds: fadeMs);
      await _transitionController.animateTo(0.0, curve: Curves.easeIn);
    } else {
      _transitionController.value = 0.0;
    }
    if (!mounted) return;
    o.onComplete?.call();
    await _autoReset(o.autoResetAfter);
  }

  // --------------------------------------------------------- shrink/vanish

  Future<void> _collapse({
    required Duration duration,
    required Curve curve,
  }) async {
    _transitionOrigin = Alignment.center;
    _transitionController.duration = duration;
    await _transitionController.animateTo(0.0, curve: curve);
  }

  Future<void> _expand({
    required Duration duration,
    required Curve curve,
  }) async {
    _transitionOrigin = Alignment.center;
    _transitionController.duration = duration;
    await _transitionController.animateTo(1.0, curve: curve);
  }

  void _resetTransition() => _transitionController.value = 1.0;

  // ------------------------------------------------------------- gestures

  void _onAutoTrigger(FabricTrigger trigger, Offset local) {
    if (!widget.enabled) return;
    final CrumpleOptions? c = widget.crumple;
    if (c != null && c.trigger == trigger) {
      _crumple(localOrigin: local);
      return;
    }
    final PinOptions? p = widget.pins;
    if (p != null && p.trigger == trigger) {
      _releasePins();
    }
  }

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
    final FabricSimulation? sim = _simulation;
    final ui.Image? image = _image;

    final bool grabByLongPress = widget.startOnLongPress;
    final FabricTrigger crumpleTrigger =
        widget.crumple?.trigger ?? FabricTrigger.none;
    final FabricTrigger pinsTrigger = widget.pins?.trigger ?? FabricTrigger.none;

    final bool autoLongPress = !grabByLongPress &&
        (crumpleTrigger == FabricTrigger.longPress ||
            pinsTrigger == FabricTrigger.longPress);
    final bool autoDoubleTap = crumpleTrigger == FabricTrigger.doubleTap ||
        pinsTrigger == FabricTrigger.doubleTap;

    final Widget content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: grabByLongPress ? null : (d) => _onDown(d.localPosition),
      onPanUpdate: grabByLongPress ? null : (d) => _onMove(d.localPosition),
      onPanEnd: grabByLongPress ? null : (_) => _onUp(),
      onPanCancel: grabByLongPress ? null : _onUp,
      onDoubleTapDown: autoDoubleTap
          ? (TapDownDetails d) => _lastDoubleTapPosition = d.localPosition
          : null,
      onDoubleTap: autoDoubleTap
          ? () => _onAutoTrigger(FabricTrigger.doubleTap, _lastDoubleTapPosition)
          : null,
      onLongPressStart: (grabByLongPress || autoLongPress)
          ? (LongPressStartDetails d) {
        if (grabByLongPress) {
          _onDown(d.localPosition);
        } else {
          _onAutoTrigger(FabricTrigger.longPress, d.localPosition);
        }
      }
          : null,
      onLongPressMoveUpdate:
      grabByLongPress ? (d) => _onMove(d.localPosition) : null,
      onLongPressEnd: grabByLongPress ? (_) => _onUp() : null,
      onLongPressCancel: grabByLongPress ? _onUp : null,
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

    // Collapse / crumple-fade overlay. At value == 1.0 (untouched state)
    // this is a plain passthrough.
    return AnimatedBuilder(
      animation: _transitionController,
      builder: (BuildContext context, Widget? child) {
        final double t = _transitionController.value;
        if (t >= 1.0) return child!;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: t,
            alignment: _transitionOrigin,
            child: child,
          ),
        );
      },
      child: content,
    );
  }
}