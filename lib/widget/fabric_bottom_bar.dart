import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../fabric_painter.dart';
import '../physics.dart';
import 'crumple.dart';
import 'fabric_elasticity.dart';
import 'theme.dart';
import 'uncrumple.dart';

/// One tab of a [FabricBottomBar].
class FabricBottomBarItem {
  const FabricBottomBarItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// A floating, pill-shaped bottom navigation bar - similar in *function* to
/// packages like `google_nav_bar` (a row of icon+label tabs with an
/// animated highlight behind the selected one) - but switching tabs plays
/// its own animation: the outgoing page crumples away toward the tapped
/// item (real cloth physics, [CrumpleOptions]) while the incoming page
/// unfolds into place from that same point (the reverse - [UncrumpleOptions]),
/// both playing together.
///
/// Pages are kept in an `IndexedStack` (state is preserved when you switch
/// away and back), which is how most bottom-bar-driven apps behave.
class FabricBottomBar extends StatefulWidget {
  const FabricBottomBar({
    super.key,
    required this.items,
    required this.pages,
    this.initialIndex = 0,
    this.onIndexChanged,
    this.physicsTransition = true,
    this.bounceDuration = const Duration(milliseconds: 260),
    this.bounceStartScale = 0.92,
    this.crumpleOptions = const CrumpleOptions(),
    this.uncrumpleOptions = const UncrumpleOptions(),
    this.elasticity = FabricElasticity.stiff,
    this.theme,
    this.shadowColor,
    this.highlightColor,
    this.shadowOpacity = 0.14,
    this.highlightOpacity = 0.10,
    this.glintStrength = 0.08,
    this.gridColumns = 18,
    this.barHeight = 64.0,
    this.barMargin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.backgroundColor,
    this.pillColor,
    this.activeColor,
    this.inactiveColor,
  })  : assert(items.length == pages.length),
        assert(items.length >= 2);

  /// One entry per tab; must be the same length as [pages].
  final List<FabricBottomBarItem> items;

  /// One page per tab, same order/length as [items].
  final List<Widget> pages;

  final int initialIndex;

  /// Called right when the tab changes (before the crumple/uncrumple
  /// animation finishes playing).
  final ValueChanged<int>? onIndexChanged;

  /// Whether switching tabs plays the crumple-away / uncrumple-in physics.
  /// True (the default) is the whole point of this widget.
  ///
  /// When false there are no screenshots, no simulations and no overlay -
  /// but the incoming page still gets a light, physics-free "pop"
  /// (scale + fade with an overshoot, see [bounceDuration] and
  /// [bounceStartScale]) so the switch keeps a bouncy feel instead of a
  /// hard cut. Cheap enough for low-end devices.
  final bool physicsTransition;

  /// Length of the physics-free pop used when [physicsTransition] is false.
  /// Use [Duration.zero] for a completely instant switch.
  final Duration bounceDuration;

  /// Scale the incoming page starts from (0..1) in the pop animation; it
  /// then overshoots 1.0 slightly and settles. Closer to 1.0 = subtler.
  final double bounceStartScale;

  /// Feel of the outgoing page's crumple-away. Only `duration`, `strength`,
  /// `twist`, `bunching` and `fadeFraction` matter here - `trigger` and the
  /// callbacks are ignored (this widget drives it directly, not a gesture).
  final CrumpleOptions crumpleOptions;

  /// Feel of the incoming page's unfold.
  final UncrumpleOptions uncrumpleOptions;

  /// Stretchiness used by both transition simulations.
  final FabricElasticity elasticity;

  /// Full [FabricTheme] override for the transition. When given it wins over
  /// the simple shading params below. Null = build one from them.
  final FabricTheme? theme;

  /// Colour of the fold shadows (null = black). Try a soft grey/blue-grey
  /// for a gentler look.
  final Color? shadowColor;

  /// Colour of the fold highlights (null = white).
  final Color? highlightColor;

  /// Strongest fold shadow opacity (0..1). Lower = lighter, less dark
  /// crumple. The old default was 0.7 (very dark).
  final double shadowOpacity;

  /// Strongest fold highlight opacity (0..1).
  final double highlightOpacity;

  /// Extra shiny glint on sharp folds (0 = off).
  final double glintStrength;

  /// Mesh resolution for the transition. Lower than [FabricEffect]'s
  /// default since two simulations run at once during a switch.
  final int gridColumns;

  final double barHeight;
  final EdgeInsets barMargin;

  /// Colours for the bar itself. Null falls back to the current [Theme].
  final Color? backgroundColor;
  final Color? pillColor;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  State<FabricBottomBar> createState() => _FabricBottomBarState();
}

class _FabricBottomBarState extends State<FabricBottomBar>
    with TickerProviderStateMixin {
  late int _index = widget.initialIndex;
  final GlobalKey _contentKey = GlobalKey();
  late final List<GlobalKey> _pageKeys =
  List<GlobalKey>.generate(widget.pages.length, (_) => GlobalKey());
  late final List<GlobalKey> _itemKeys =
  List<GlobalKey>.generate(widget.items.length, (_) => GlobalKey());

  _BarTransition? _transition;
  bool _switching = false;

  /// Drives the physics-free pop used when `physicsTransition` is false.
  /// Rests at 1.0 ("settled") and is only ever restarted from 0.0 on a tab
  /// tap in that mode - so with physics on it never leaves 1.0 and has no
  /// effect on the crumple/uncrumple flow.
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    value: 1.0,
    duration: widget.bounceDuration,
  );

  /// easeOutBack overshoots past the end value, which is the "bouncy" part.
  late Animation<double> _bounceScale = _buildBounceScale();

  /// Soft fade-in so the page doesn't just pop.
  late final Animation<double> _bounceFade = Tween<double>(begin: 0.0, end: 1.0)
      .animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOut));

  Animation<double> _buildBounceScale() {
    return Tween<double>(
      begin: widget.bounceStartScale.clamp(0.0, 1.0).toDouble(),
      end: 1.0,
    ).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOutBack),
    );
  }

  @override
  void didUpdateWidget(covariant FabricBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bounceDuration != widget.bounceDuration) {
      _bounceController.duration = widget.bounceDuration;
    }
    if (oldWidget.bounceStartScale != widget.bounceStartScale) {
      _bounceScale = _buildBounceScale();
    }
  }

  @override
  void dispose() {
    _transition?.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  FabricTheme _resolveTheme() {
    final FabricTheme? full = widget.theme;
    if (full != null) return full;
    return FabricTheme(
      shadowColor: widget.shadowColor ?? const Color(0xFF000000),
      highlightColor: widget.highlightColor ?? const Color(0xFFFFFFFF),
      maxShadowOpacity: widget.shadowOpacity.clamp(0.0, 1.0).toDouble(),
      maxHighlightOpacity: widget.highlightOpacity.clamp(0.0, 1.0).toDouble(),
      specularStrength: math.max(0.0, widget.glintStrength),
    );
  }

  Future<ui.Image?> _capture(GlobalKey key, double pixelRatio) async {
    final RenderObject? object = key.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    try {
      return await object.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onItemTap(int newIndex) async {
    if (newIndex == _index || _switching) return;

    // No physics: no screenshots, no simulations, no overlay - but keep the
    // switch lively with a light scale + fade pop (overshoot = bounce).
    if (!widget.physicsTransition) {
      setState(() => _index = newIndex);
      widget.onIndexChanged?.call(newIndex);
      if (widget.bounceDuration > Duration.zero) {
        _bounceController.forward(from: 0.0);
      }
      return;
    }

    final RenderBox? contentBox =
    _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null || !contentBox.hasSize) {
      setState(() => _index = newIndex);
      widget.onIndexChanged?.call(newIndex);
      return;
    }

    _switching = true;
    try {
      final RenderBox? itemBox =
      _itemKeys[newIndex].currentContext?.findRenderObject() as RenderBox?;
      final Offset originGlobal = (itemBox != null && itemBox.attached)
          ? itemBox.localToGlobal(itemBox.size.center(Offset.zero))
          : contentBox.localToGlobal(contentBox.size.center(Offset.zero));
      final Offset originLocal = contentBox.globalToLocal(originGlobal);
      final double pixelRatio = View.of(context).devicePixelRatio;

      final ui.Image? oldImage = await _capture(_pageKeys[_index], pixelRatio);
      if (!mounted) {
        oldImage?.dispose();
        return;
      }

      setState(() => _index = newIndex);
      widget.onIndexChanged?.call(newIndex);
      // Let the now-selected page in the IndexedStack actually paint once
      // before we screenshot it.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) {
        oldImage?.dispose();
        return;
      }

      final ui.Image? newImage =
      await _capture(_pageKeys[newIndex], pixelRatio);
      if (oldImage == null || newImage == null) {
        oldImage?.dispose();
        newImage?.dispose();
        return;
      }

      final _BarTransition transition = _BarTransition(
        vsync: this,
        oldImage: oldImage,
        newImage: newImage,
        size: contentBox.size,
        devicePixelRatio: pixelRatio,
        originLocal: originLocal,
        crumpleOptions: widget.crumpleOptions,
        uncrumpleOptions: widget.uncrumpleOptions,
        elasticity: widget.elasticity,
        theme: _resolveTheme(),
        gridColumns: widget.gridColumns,
        onDone: () {
          final _BarTransition? t = _transition;
          if (mounted) setState(() => _transition = null);
          t?.dispose();
        },
      );
      if (!mounted) {
        transition.dispose();
        return;
      }
      setState(() {
        _transition?.dispose();
        _transition = transition;
      });
    } finally {
      _switching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double reservedBottom = widget.barHeight + widget.barMargin.vertical;

    // The content is built once and passed as the AnimatedBuilder `child`,
    // so pages are NOT rebuilt on every bounce frame. The Opacity/Transform
    // wrappers are always present (never added/removed), so page state and
    // keys stay stable; at value 1.0 they cost nothing.
    final Widget content = KeyedSubtree(
      key: _contentKey,
      child: IndexedStack(
        index: _index,
        children: <Widget>[
          for (int i = 0; i < widget.pages.length; i++)
            RepaintBoundary(key: _pageKeys[i], child: widget.pages[i]),
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: reservedBottom,
          child: AnimatedBuilder(
            animation: _bounceController,
            child: content,
            builder: (BuildContext context, Widget? child) {
              return Opacity(
                opacity: _bounceFade.value.clamp(0.0, 1.0).toDouble(),
                child: Transform.scale(
                  scale: _bounceScale.value,
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            },
          ),
        ),
        if (_transition != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: reservedBottom,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _transition!.frame,
                builder: (BuildContext context, Widget? _) {
                  return CustomPaint(
                      painter: _BarTransitionPainter(_transition!));
                },
              ),
            ),
          ),
        Positioned(
          left: widget.barMargin.left,
          right: widget.barMargin.right,
          bottom: widget.barMargin.bottom,
          height: widget.barHeight,
          child: _FabricPillBar(
            items: widget.items,
            itemKeys: _itemKeys,
            selectedIndex: _index,
            onTap: _onItemTap,
            backgroundColor: widget.backgroundColor,
            pillColor: widget.pillColor,
            activeColor: widget.activeColor,
            inactiveColor: widget.inactiveColor,
          ),
        ),
      ],
    );
  }
}

/// Owns the two short-lived simulations (crumple-away / unfold-in) for one
/// tab switch, and the ticker that steps them both every frame.
class _BarTransition {
  _BarTransition({
    required TickerProvider vsync,
    required this.oldImage,
    required this.newImage,
    required Size size,
    required this.devicePixelRatio,
    required Offset originLocal,
    required this.crumpleOptions,
    required this.uncrumpleOptions,
    required FabricElasticity elasticity,
    required FabricTheme theme,
    required int gridColumns,
    required this.onDone,
  })  : oldSim = _buildSim(size, gridColumns, elasticity),
        newSim = _buildSim(size, gridColumns, elasticity) {
    oldForce = CrumpleForce(
      targetX: originLocal.dx,
      targetY: originLocal.dy,
      options: crumpleOptions,
    );
    oldForce.start(oldSim);
    oldSim.addForce(oldForce);

    newForce = UncrumpleForce(options: uncrumpleOptions);
    newForce.seedAndStart(newSim, originLocal.dx, originLocal.dy);
    newSim.addForce(newForce);

    oldPainter = FabricPainter(oldSim, oldImage,
        devicePixelRatio: devicePixelRatio, theme: theme);
    newPainter = FabricPainter(newSim, newImage,
        devicePixelRatio: devicePixelRatio, theme: theme);

    final int crumpleMs = crumpleOptions.duration.inMilliseconds;
    _fadeStartMs =
        (crumpleMs * (1.0 - crumpleOptions.fadeFraction.clamp(0.0, 1.0)))
            .round();
    _totalMs = math.max(crumpleMs, uncrumpleOptions.duration.inMilliseconds);

    _ticker = vsync.createTicker(_onTick)..start();
  }

  final ui.Image oldImage;
  final ui.Image newImage;
  final double devicePixelRatio;
  final CrumpleOptions crumpleOptions;
  final UncrumpleOptions uncrumpleOptions;
  final VoidCallback onDone;

  final FabricSimulation oldSim;
  final FabricSimulation newSim;
  late final CrumpleForce oldForce;
  late final UncrumpleForce newForce;
  late final FabricPainter oldPainter;
  late final FabricPainter newPainter;

  /// Bumped every stepped frame - drives the [AnimatedBuilder] repaint.
  final ValueNotifier<int> frame = ValueNotifier<int>(0);

  /// 1.0 -> 0.0 over the tail of [crumpleOptions.duration].
  double oldOpacity = 1.0;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _accumulator = 0.0;
  late final int _fadeStartMs;
  late final int _totalMs;
  bool _done = false;
  bool _disposed = false;

  static FabricSimulation _buildSim(
      Size size,
      int cols,
      FabricElasticity elasticity,
      ) {
    final int safeCols = math.max(4, cols);
    final double spacing = size.width / math.max(1, safeCols - 1);
    final int rows =
    math.max(4, (size.height / spacing).round() + 1).clamp(4, 160);
    return FabricSimulation(
      width: size.width,
      height: size.height,
      cols: safeCols,
      rows: rows,
      elasticity: elasticity,
    );
  }

  void _onTick(Duration elapsed) {
    if (_done) return;

    double dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt > 0.05) dt = 0.05;
    _accumulator += dt;

    int steps = 0;
    while (_accumulator >= FabricSimulation.timeStep && steps < 3) {
      oldSim.step();
      newSim.step();
      _accumulator -= FabricSimulation.timeStep;
      steps++;
    }
    if (steps == 3) _accumulator = 0.0;

    final int ms = elapsed.inMilliseconds;
    if (ms >= _fadeStartMs) {
      final int fadeSpan =
      math.max(1, crumpleOptions.duration.inMilliseconds - _fadeStartMs);
      oldOpacity = (1.0 - (ms - _fadeStartMs) / fadeSpan).clamp(0.0, 1.0);
    }

    frame.value++;

    if (ms >= _totalMs) {
      _done = true;
      _ticker.stop();
      onDone();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _done = true;
    _ticker.stop();
    _ticker.dispose();
    oldForce.stop();
    newForce.stop();
    frame.dispose();
    oldImage.dispose();
    newImage.dispose();
  }
}

class _BarTransitionPainter extends CustomPainter {
  _BarTransitionPainter(this.t) : super(repaint: t.frame);

  final _BarTransition t;

  @override
  void paint(Canvas canvas, Size size) {
    // Incoming page underneath, unfolding into place.
    t.newPainter.paint(canvas, size);
    // Outgoing page on top, crumpling away and fading out over it.
    if (t.oldOpacity > 0.0) {
      final Rect bounds = Offset.zero & size;
      canvas.saveLayer(
          bounds, Paint()..color = Color.fromRGBO(0, 0, 0, t.oldOpacity));
      t.oldPainter.paint(canvas, size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BarTransitionPainter oldDelegate) => true;
}

/// The floating pill-shaped tab row itself - purely visual/gesture, no
/// physics here.
class _FabricPillBar extends StatelessWidget {
  const _FabricPillBar({
    required this.items,
    required this.itemKeys,
    required this.selectedIndex,
    required this.onTap,
    this.backgroundColor,
    this.pillColor,
    this.activeColor,
    this.inactiveColor,
  });

  final List<FabricBottomBarItem> items;
  final List<GlobalKey> itemKeys;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Color? backgroundColor;
  final Color? pillColor;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bg = backgroundColor ?? scheme.surface;
    final Color pill = pillColor ?? scheme.primaryContainer;
    final Color active = activeColor ?? scheme.onPrimaryContainer;
    final Color inactive = inactiveColor ?? scheme.onSurfaceVariant;

    return Material(
      color: bg,
      elevation: 8,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double itemWidth = constraints.maxWidth / items.length;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: itemWidth * selectedIndex + 6,
                top: 6,
                bottom: 6,
                width: itemWidth - 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: pill,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: InkWell(
                        key: itemKeys[i],
                        onTap: () => onTap(i),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                items[i].icon,
                                size: 22,
                                color: i == selectedIndex ? active : inactive,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                items[i].label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: i == selectedIndex
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i == selectedIndex ? active : inactive,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}