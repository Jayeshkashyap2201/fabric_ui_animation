import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'fabric_sounds.dart';

/// Which side the page is lifted from - like a real book: turning forward
/// lifts the right edge, turning back lifts the left edge.
enum CurlEdge { left, right }

/// Settings for the book-style page turn. Every field has a default; pass
/// this to [FabricPageTurn] once (and/or to a single
/// [pushWithPageCurl] / [popWithPageCurl] call) and change only what you need.
class PageCurlOptions {
  /// How long a turn takes (also scales how long a released drag settles).
  final Duration duration;

  final Curve curve;

  /// Radius of the paper roll in logical pixels. Smaller = tighter curl.
  final double rollRadius;

  /// Tilt of the fold line in radians. 0 = a straight vertical fold, larger
  /// = the corner peels first (more natural). Roughly 0.1 - 0.3.
  final double curlAngle;

  /// Camera distance in pixels. Smaller = stronger perspective (the lifted
  /// part looks bigger / closer). Larger = flatter.
  final double perspective;

  /// Colour of the paper's back side. Null = the theme's scaffold background,
  /// so it matches light and dark apps automatically.
  final Color? backColor;

  /// How much of the page content shows faintly through its back (0..1).
  final double backShowThrough;

  /// Strength of the shading and cast shadows (0 = none, 1 = default).
  final double shadowStrength;

  /// When true, [FabricPageTurn] lets the user turn the page with a finger
  /// drag from the page edge (right edge = forward, left edge = back).
  final bool interactive;

  /// Width of the strip along each edge where a drag can start.
  final double dragEdgeExtent;

  /// Releasing a drag after this fraction of the page width completes the
  /// turn (a fast fling completes it too); otherwise it snaps back.
  final double completeThreshold;

  /// Fling speed in px/s that completes a drag regardless of distance.
  final double flingVelocity;

  /// Optional sound / haptic hook (`onPageTurn`).
  final FabricSounds? sounds;

  const PageCurlOptions({
    this.duration = const Duration(milliseconds: 500),
    this.curve = Curves.easeInOutCubic,
    this.rollRadius = 38.0,
    this.curlAngle = 0.20,
    this.perspective = 1100.0,
    this.backColor,
    this.backShowThrough = 0.20,
    this.shadowStrength = 1.0,
    this.interactive = false,
    this.dragEdgeExtent = 56.0,
    this.completeThreshold = 0.30,
    this.flingVelocity = 600.0,
    this.sounds,
  });

  PageCurlOptions copyWith({
    Duration? duration,
    Curve? curve,
    double? rollRadius,
    double? curlAngle,
    double? perspective,
    Color? backColor,
    double? backShowThrough,
    double? shadowStrength,
    bool? interactive,
    double? dragEdgeExtent,
    double? completeThreshold,
    double? flingVelocity,
    FabricSounds? sounds,
  }) {
    return PageCurlOptions(
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
      rollRadius: rollRadius ?? this.rollRadius,
      curlAngle: curlAngle ?? this.curlAngle,
      perspective: perspective ?? this.perspective,
      backColor: backColor ?? this.backColor,
      backShowThrough: backShowThrough ?? this.backShowThrough,
      shadowStrength: shadowStrength ?? this.shadowStrength,
      interactive: interactive ?? this.interactive,
      dragEdgeExtent: dragEdgeExtent ?? this.dragEdgeExtent,
      completeThreshold: completeThreshold ?? this.completeThreshold,
      flingVelocity: flingVelocity ?? this.flingVelocity,
      sounds: sounds ?? this.sounds,
    );
  }
}

/// How far the page is turned: [progress] 0 = flat, 1 = gone; [angle] is the
/// fold tilt (null = the options' `curlAngle`).
@immutable
class PageCurlPose {
  const PageCurlPose(this.progress, [this.angle]);

  final double progress;
  final double? angle;
}

class _RollCell {
  const _RollCell(this.s, this.topLeft);
  final double s;
  final int topLeft;
}

/// Draws a captured page being lifted from one edge and rolled over, with
/// its back side showing, like a real paper page turn.
///
/// The page is a mesh. Along the fold line it splits into three parts:
/// the flat rest, a half-cylinder roll, and the part that has already been
/// flipped over (drawn mirrored, tinted like paper, on top of the flat rest).
/// Depth comes from real perspective projection, per-vertex lighting on the
/// cylinder normals, a highlight along the crest, and soft cast shadows on
/// the page underneath and on the flat rest.
class PageCurlPainter extends CustomPainter {
  PageCurlPainter({
    required this.pose,
    required this.image,
    required this.edge,
    required this.options,
    required this.backColor,
    this.devicePixelRatio = 1.0,
  }) : super(repaint: pose);

  final ValueListenable<PageCurlPose> pose;
  final ui.Image image;
  final CurlEdge edge;
  final PageCurlOptions options;
  final Color backColor;
  final double devicePixelRatio;

  static const int _cols = 56;
  static const int _rows = 40;

  // Light from the top, slightly to the right of the viewer.
  static const double _lx = 0.26;
  static const double _ly = -0.38;
  static const double _lz = 0.89;

  late final Paint _texturePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.medium
    ..shader = ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
    );

  final Paint _tintPaint = Paint()
    ..isAntiAlias = false
    ..color = const Color(0xFFFFFFFF);

  static double _smooth(double a, double b, double x) {
    final double t = ((x - a) / (b - a)).clamp(0.0, 1.0).toDouble();
    return t * t * (3.0 - 2.0 * t);
  }

  static int _channel(double v) => v.round().clamp(0, 255).toInt();

  /// Overlay colour (paper back + shading) for one mesh vertex.
  int _tintFor(double theta, double nx, double ny, double nz) {
    final double strength = options.shadowStrength;
    final double diff = math.max(0.0, nx * _lx + ny * _ly + nz * _lz) - _lz;

    double shadow = 0.0;
    double light = 0.0;
    if (diff < 0.0) {
      shadow = math.min(0.40, -diff * 0.50) * strength;
    } else {
      light = math.min(0.30, diff * 0.90);
    }
    final double bump = (theta - 2.35) / 0.42;
    final double sheen = math.exp(-bump * bump) * 0.26;
    if (sheen > light) light = sheen;

    final double paperBase = 1.0 - options.backShowThrough.clamp(0.0, 1.0);
    final double paperA =
        paperBase * _smooth(math.pi / 2 - 0.25, math.pi / 2 + 0.25, theta);

    final int pv = backColor.value;
    final double pr = ((pv >> 16) & 0xFF).toDouble();
    final double pg = ((pv >> 8) & 0xFF).toDouble();
    final double pb = (pv & 0xFF).toDouble();

    final bool useLight = light > shadow;
    final double sa = useLight ? light : shadow;
    final double sc = useLight ? 255.0 : 0.0;

    final double outA = sa + paperA * (1.0 - sa);
    if (outA <= 0.0) return 0;
    final double k = paperA * (1.0 - sa);
    final double outR = (sc * sa + pr * k) / outA;
    final double outG = (sc * sa + pg * k) / outA;
    final double outB = (sc * sa + pb * k) / outA;
    return (_channel(outA * 255.0) << 24) |
    (_channel(outR) << 16) |
    (_channel(outG) << 8) |
    _channel(outB);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final PageCurlPose p = pose.value;
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0 || p.progress >= 1.0) return;
    final double progress = p.progress.clamp(0.0, 1.0).toDouble();

    // Canonical geometry: the fold sweeps from the right edge to the left.
    // For the left edge everything is mirrored on the way to the screen.
    final bool flipX = edge == CurlEdge.left;
    // Real paper doesn't lift into a full-size roll instantly - the curl
    // starts tight (near zero) and grows to its full radius over the first
    // slice of the turn. Without this, the very first frames show a
    // constant-width shadow/roll snapping in abruptly instead of easing in.
    final double r = math.max(4.0, options.rollRadius * _smooth(0.02, 0.18, progress));
    final double a = p.angle ?? options.curlAngle;
    final double ca = math.cos(a);
    final double sa = math.sin(a);
    final double tn = math.tan(a).abs();
    final double piR = math.pi * r;
    final double cy = h / 2;
    final double halfW = w / 2;
    final double focal = options.perspective;

    // foldStart: nothing lifted yet. foldEnd: everything gone off-screen.
    final double foldStart = w + cy * tn + 1.0;
    final double foldEnd = -(r + cy * tn) - 4.0;
    final double foldX = foldStart + (foldEnd - foldStart) * progress;

    Offset pt(double x, double y) => Offset(flipX ? w - x : x, y);

    const int cols = _cols;
    const int rows = _rows;
    const int stride = cols + 1;
    final int vertexCount = stride * (rows + 1);
    final Float32List positions = Float32List(vertexCount * 2);
    final Float32List uv = Float32List(vertexCount * 2);
    final Int32List tint = Int32List(vertexCount);
    final Float64List sValues = Float64List(vertexCount);

    for (int j = 0; j <= rows; j++) {
      final double y = h * j / rows;
      for (int i = 0; i <= cols; i++) {
        final double x = w * i / cols;
        final int vi = j * stride + i;

        // s: distance from the fold line along the curl direction,
        // t: distance along the fold line.
        final double dx = x - foldX;
        final double dy = y - cy;
        final double s = dx * ca + dy * sa;
        final double t = -dx * sa + dy * ca;

        double sp = s;
        double z = 0.0;
        double theta = 0.0;
        double nx = 0.0;
        double ny = 0.0;
        double nz = 1.0;
        if (s > 0.0) {
          if (s < piR) {
            theta = s / r;
            final double st = math.sin(theta);
            final double ct = math.cos(theta);
            sp = r * st;
            z = r * (1.0 - ct);
            // Outward (back-side) normal of the roll.
            nx = st * ca;
            ny = st * sa;
            nz = -ct;
          } else {
            // Already flipped over: lies on top of the flat rest.
            theta = math.pi;
            sp = piR - s;
            z = 2.0 * r;
          }
        }

        final double px = foldX + sp * ca - t * sa;
        final double py = cy + sp * sa + t * ca;
        final double scale = focal / math.max(focal - z, 1.0);
        final double sx = halfW + (px - halfW) * scale;
        final double sy = cy + (py - cy) * scale;

        positions[vi * 2] = flipX ? w - sx : sx;
        positions[vi * 2 + 1] = sy;
        uv[vi * 2] = (flipX ? w - x : x) * devicePixelRatio;
        uv[vi * 2 + 1] = y * devicePixelRatio;
        sValues[vi] = s;
        tint[vi] = s > 0.0 ? _tintFor(theta, nx, ny, nz) : 0;
      }
    }

    // Sort the cells into flat / roll / flipped.
    final List<int> flat = <int>[];
    final List<_RollCell> roll = <_RollCell>[];
    final List<int> flipped = <int>[];
    void addCell(List<int> target, int tl) {
      final int tr = tl + 1;
      final int bl = tl + stride;
      final int br = bl + 1;
      target
        ..add(tl)
        ..add(tr)
        ..add(bl)
        ..add(tr)
        ..add(br)
        ..add(bl);
    }

    for (int j = 0; j < rows; j++) {
      for (int i = 0; i < cols; i++) {
        final int tl = j * stride + i;
        final double sc = (sValues[tl] +
            sValues[tl + 1] +
            sValues[tl + stride] +
            sValues[tl + stride + 1]) *
            0.25;
        if (sc <= 0.0) {
          addCell(flat, tl);
        } else if (sc < piR) {
          roll.add(_RollCell(sc, tl));
        } else {
          addCell(flipped, tl);
        }
      }
    }
    // Lowest part of the roll first, so the top of it covers it.
    roll.sort((_RollCell x, _RollCell y) => x.s.compareTo(y.s));
    final List<int> rollIndices = <int>[];
    for (final _RollCell cell in roll) {
      addCell(rollIndices, cell.topLeft);
    }

    final double strength = options.shadowStrength;

    // 1) Shadow of the lifted page on the page revealed underneath.
    if (strength > 0.0) {
      final double reach = 3.6 * r;
      final double big = h + w + 200.0;
      final double px0 = foldX;
      final double py0 = cy;
      final double ux = -sa;
      final double uy = ca;
      final Path band = Path()
        ..moveTo(pt(px0 + ux * big, py0 + uy * big).dx,
            pt(px0 + ux * big, py0 + uy * big).dy)
        ..lineTo(pt(px0 - ux * big, py0 - uy * big).dx,
            pt(px0 - ux * big, py0 - uy * big).dy)
        ..lineTo(pt(px0 - ux * big + ca * reach, py0 - uy * big + sa * reach).dx,
            pt(px0 - ux * big + ca * reach, py0 - uy * big + sa * reach).dy)
        ..lineTo(pt(px0 + ux * big + ca * reach, py0 + uy * big + sa * reach).dx,
            pt(px0 + ux * big + ca * reach, py0 + uy * big + sa * reach).dy)
        ..close();
      final ui.Gradient gradient = ui.Gradient.linear(
        pt(px0, py0),
        pt(px0 + ca * reach, py0 + sa * reach),
        <Color>[
          Color.fromRGBO(0, 0, 0, 0.36 * strength),
          Color.fromRGBO(0, 0, 0, 0.227 * strength),
          Color.fromRGBO(0, 0, 0, 0.119 * strength),
          Color.fromRGBO(0, 0, 0, 0.039 * strength),
          const Color(0x00000000),
        ],
        const <double>[0.0, 0.25, 0.5, 0.75, 1.0],
      );
      canvas.drawPath(band, Paint()..shader = gradient);
    }

    // 2) The flat rest of the page (front side).
    if (flat.isNotEmpty) {
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          textureCoordinates: uv,
          indices: Uint16List.fromList(flat),
        ),
        BlendMode.srcOver,
        _texturePaint,
      );
    }

    // 3) Soft shadow of the flipped part falling on the flat rest.
    if (strength > 0.0 && flipped.isNotEmpty) {
      final List<Offset> corners = <Offset>[
        Offset.zero,
        Offset(w, 0),
        Offset(w, h),
        Offset(0, h),
      ];
      double sOf(Offset c) => (c.dx - foldX) * ca + (c.dy - cy) * sa;
      final List<Offset> clipped = <Offset>[];
      for (int k = 0; k < corners.length; k++) {
        final Offset cur = corners[k];
        final Offset nxt = corners[(k + 1) % corners.length];
        final double sCur = sOf(cur);
        final double sNxt = sOf(nxt);
        final bool inCur = sCur >= piR;
        final bool inNxt = sNxt >= piR;
        if (inCur) clipped.add(cur);
        if (inCur != inNxt) {
          final double tt = (piR - sCur) / (sNxt - sCur);
          clipped.add(Offset(cur.dx + (nxt.dx - cur.dx) * tt,
              cur.dy + (nxt.dy - cur.dy) * tt));
        }
      }
      if (clipped.length >= 3) {
        final Path shadow = Path();
        for (int k = 0; k < clipped.length; k++) {
          final Offset c = clipped[k];
          final double s = sOf(c);
          final double t = -(c.dx - foldX) * sa + (c.dy - cy) * ca;
          final double sp = piR - s;
          final double px = foldX + sp * ca - t * sa - r * 0.18;
          final double py = cy + sp * sa + t * ca + r * 0.24;
          final double scale = focal / math.max(focal - 2.0 * r, 1.0);
          final Offset o = pt(halfW + (px - halfW) * scale, cy + (py - cy) * scale);
          if (k == 0) {
            shadow.moveTo(o.dx, o.dy);
          } else {
            shadow.lineTo(o.dx, o.dy);
          }
        }
        shadow.close();
        canvas.drawPath(
          shadow,
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, 0.43 * strength)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.24),
        );
      }
    }

    // 4) The roll (its visible top half shows the paper's back).
    if (rollIndices.isNotEmpty) {
      final Uint16List idx = Uint16List.fromList(rollIndices);
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          textureCoordinates: uv,
          indices: idx,
        ),
        BlendMode.srcOver,
        _texturePaint,
      );
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          colors: tint,
          indices: idx,
        ),
        BlendMode.modulate,
        _tintPaint,
      );
    }

    // 5) The part already flipped over: mirrored content faintly showing
    //    through paper, drawn last so it lies on top of everything.
    if (flipped.isNotEmpty) {
      final Uint16List idx = Uint16List.fromList(flipped);
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          textureCoordinates: uv,
          indices: idx,
        ),
        BlendMode.srcOver,
        _texturePaint,
      );
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          positions,
          colors: tint,
          indices: idx,
        ),
        BlendMode.modulate,
        _tintPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PageCurlPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.edge != edge ||
        oldDelegate.options != options ||
        oldDelegate.backColor != backColor;
  }
}

/// The route [pushWithPageCurl] uses: no transition of its own (the curl
/// overlay is the transition). When [opaque] is false the page underneath
/// stays painted - which is what lets a finger drag turn BACK to it in real
/// time (used automatically when `PageCurlOptions.interactive` is true).
class PageCurlRoute<T> extends PageRouteBuilder<T> {
  PageCurlRoute({required Widget page, bool opaque = false, super.settings})
      : super(
    opaque: opaque,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        ) =>
    page,
  );
}

// One turn at a time, app-wide.
bool _curlBusy = false;

Future<ui.Image?> _capture(GlobalKey key, double pixelRatio) async {
  for (int attempt = 0; attempt < 2; attempt++) {
    final RenderObject? object = key.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    try {
      return await object.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      // Not painted yet - wait one frame and try once more.
      await SchedulerBinding.instance.endOfFrame;
    }
  }
  return null;
}

/// Owns the overlay that shows the curling snapshot above everything.
class _CurlSession {
  _CurlSession({
    required this.overlay,
    required this.vsync,
    required this.image,
    required this.devicePixelRatio,
    required this.edge,
    required this.options,
    required this.backColor,
  });

  final OverlayState overlay;
  final TickerProvider vsync;
  final ui.Image image;
  final double devicePixelRatio;
  final CurlEdge edge;
  final PageCurlOptions options;
  final Color backColor;

  final ValueNotifier<PageCurlPose> pose =
  ValueNotifier<PageCurlPose>(const PageCurlPose(0.0));

  OverlayEntry? _entry;
  AnimationController? _controller;
  bool _disposed = false;

  /// Insert AFTER any Navigator push/pop: the navigator re-orders its own
  /// overlay entries on every route change, so an entry added before would
  /// end up hidden underneath the new page.
  void show() {
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: PageCurlPainter(
              pose: pose,
              image: image,
              edge: edge,
              options: options,
              backColor: backColor,
              devicePixelRatio: devicePixelRatio,
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  Future<void> animateTo(
      double target, {
        required Duration duration,
        required Curve curve,
      }) async {
    if (_disposed) return;
    _controller?.dispose();
    _controller = null;

    final double from = pose.value.progress;
    final double? angle = pose.value.angle;
    if (duration <= Duration.zero || (from - target).abs() < 1e-4) {
      pose.value = PageCurlPose(target, angle);
      return;
    }

    final AnimationController controller =
    AnimationController(vsync: vsync, duration: duration);
    _controller = controller;
    final Animation<double> curved =
    CurvedAnimation(parent: controller, curve: curve);
    void tick() {
      pose.value = PageCurlPose(from + (target - from) * curved.value, angle);
    }

    curved.addListener(tick);
    try {
      await controller.forward().orCancel;
      pose.value = PageCurlPose(target, angle);
    } on TickerCanceled {
      // Disposed mid-way - nothing left to do.
    } finally {
      curved.removeListener(tick);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller?.dispose();
    _controller = null;
    final OverlayEntry? entry = _entry;
    _entry = null;
    entry?.remove();
    entry?.dispose();
    final ui.Image img = image;
    final ValueNotifier<PageCurlPose> notifier = pose;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      img.dispose();
      notifier.dispose();
    });
  }
}

class _CurlSource {
  const _CurlSource(this.key, this.options);
  final GlobalKey key;
  final PageCurlOptions options;
}

_CurlSource _resolveSource(
    BuildContext context,
    GlobalKey? pageKey,
    PageCurlOptions? options,
    ) {
  final FabricPageTurnState? scope = FabricPageTurn.maybeOf(context);
  final GlobalKey? key = pageKey ?? scope?.boundaryKey;
  if (key == null) {
    throw FlutterError(
      'pushWithPageCurl / popWithPageCurl need a FabricPageTurn above this '
          'context (wrap your page with FabricPageTurn), or an explicit pageKey '
          'on a RepaintBoundary around the page.',
    );
  }
  return _CurlSource(
    key,
    options ?? scope?.widget.options ?? const PageCurlOptions(),
  );
}

/// Pushes [page] and reveals it by lifting the current screen from the
/// right edge and rolling it over - like turning forward in a book.
///
/// Needs a [FabricPageTurn] around the current page (or [pageKey]). Leave
/// [options] out to use that widget's options.
Future<T?> pushWithPageCurl<T>(
    BuildContext context, {
      required Widget page,
      PageCurlOptions? options,
      GlobalKey? pageKey,
    }) async {
  if (_curlBusy) return null;
  final _CurlSource source = _resolveSource(context, pageKey, options);
  final NavigatorState navigator = Navigator.of(context);
  final OverlayState overlay = Overlay.of(context);
  final double pixelRatio = View.of(context).devicePixelRatio;
  final Color back =
      source.options.backColor ?? Theme.of(context).scaffoldBackgroundColor;

  _curlBusy = true;
  try {
    final ui.Image? snapshot = await _capture(source.key, pixelRatio);
    if (snapshot == null || !navigator.mounted) {
      snapshot?.dispose();
      return null;
    }
    final _CurlSession session = _CurlSession(
      overlay: overlay,
      vsync: navigator,
      image: snapshot,
      devicePixelRatio: pixelRatio,
      edge: CurlEdge.right,
      options: source.options,
      backColor: back,
    );
    // Navigate first, cover it with the overlay second (same frame).
    final Future<T?> pushed = navigator.push<T>(
      PageCurlRoute<T>(page: page, opaque: !source.options.interactive),
    );
    session.show();
    source.options.sounds?.onPageTurn?.call();
    await session.animateTo(
      1.0,
      duration: source.options.duration,
      curve: source.options.curve,
    );
    session.dispose();
    return pushed;
  } finally {
    _curlBusy = false;
  }
}

/// Pops the current page and reveals the previous one by lifting the current
/// screen from the left edge and rolling it over - like turning back a page.
Future<void> popWithPageCurl(
    BuildContext context, {
      PageCurlOptions? options,
      GlobalKey? pageKey,
    }) async {
  if (_curlBusy) return;
  final NavigatorState navigator = Navigator.of(context);
  if (!navigator.canPop()) return;
  final _CurlSource source = _resolveSource(context, pageKey, options);
  final OverlayState overlay = Overlay.of(context);
  final double pixelRatio = View.of(context).devicePixelRatio;
  final Color back =
      source.options.backColor ?? Theme.of(context).scaffoldBackgroundColor;

  _curlBusy = true;
  try {
    final ui.Image? snapshot = await _capture(source.key, pixelRatio);
    if (snapshot == null || !navigator.mounted) {
      snapshot?.dispose();
      return;
    }
    final _CurlSession session = _CurlSession(
      overlay: overlay,
      vsync: navigator,
      image: snapshot,
      devicePixelRatio: pixelRatio,
      edge: CurlEdge.left,
      options: source.options,
      backColor: back,
    );
    navigator.pop();
    session.show();
    source.options.sounds?.onPageTurn?.call();
    await session.animateTo(
      1.0,
      duration: source.options.duration,
      curve: source.options.curve,
    );
    session.dispose();
  } finally {
    _curlBusy = false;
  }
}

/// Wrap a page (usually the whole Scaffold) with this to enable page curl on
/// it. It owns the RepaintBoundary that gets screenshotted, so
/// [pushWithPageCurl] / [popWithPageCurl] / the ready-made buttons find it
/// on their own - no keys to create.
///
/// With `options.interactive: true` the user can also turn pages with a
/// finger: drag from the right edge to go forward (needs [nextPageBuilder]),
/// from the left edge to go back (only on pages opened with
/// [pushWithPageCurl] / [PageCurlRoute]).
class FabricPageTurn extends StatefulWidget {
  const FabricPageTurn({
    super.key,
    required this.child,
    this.options = const PageCurlOptions(),
    this.nextPageBuilder,
  });

  final Widget child;
  final PageCurlOptions options;

  /// Builds the page a forward drag opens. Null = no forward drag.
  final WidgetBuilder? nextPageBuilder;

  static FabricPageTurnState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<FabricPageTurnState>();
  }

  @override
  State<FabricPageTurn> createState() => FabricPageTurnState();
}

class FabricPageTurnState extends State<FabricPageTurn> {
  /// Key of the RepaintBoundary around [FabricPageTurn.child].
  final GlobalKey boundaryKey = GlobalKey();

  bool _hidden = false;

  _CurlSession? _session;
  NavigatorState? _navigator;
  bool _dragActive = false;
  bool _dragEnded = false;
  CurlEdge _dragEdge = CurlEdge.right;
  double _dragStartX = 0.0;
  double _dragX = 0.0;
  double _dragWidth = 1.0;
  double _dragHeight = 1.0;
  double _dragAngle = 0.2;
  double _endVelocity = 0.0;

  @override
  void dispose() {
    _session?.dispose();
    _session = null;
    super.dispose();
  }

  bool _canDragBack(BuildContext context) {
    // Turning back live needs the previous page to still be painted, which
    // only holds for a non-opaque PageCurlRoute.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    return Navigator.canPop(context) && route is PageCurlRoute && !route.opaque;
  }

  Offset? _toLocal(Offset global) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  Future<void> _onDragStart(CurlEdge edge, DragStartDetails details) async {
    if (_curlBusy || _dragActive) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (edge == CurlEdge.right && widget.nextPageBuilder == null) return;

    _curlBusy = true;
    _dragActive = true;
    _dragEnded = false;
    _dragEdge = edge;
    _endVelocity = 0.0;
    final Offset local = box.globalToLocal(details.globalPosition);
    _dragWidth = box.size.width;
    _dragHeight = box.size.height;
    _dragStartX = local.dx;
    _dragX = local.dx;
    // The corner nearest the finger peels first.
    final double maxAngle = widget.options.curlAngle;
    _dragAngle = local.dy < _dragHeight / 2 ? -maxAngle : maxAngle;

    final NavigatorState navigator = Navigator.of(context);
    final OverlayState overlay = Overlay.of(context);
    final double pixelRatio = View.of(context).devicePixelRatio;
    final PageCurlOptions options = widget.options;
    final Color back =
        options.backColor ?? Theme.of(context).scaffoldBackgroundColor;

    final ui.Image? snapshot = await _capture(boundaryKey, pixelRatio);
    if (snapshot == null || !mounted) {
      snapshot?.dispose();
      _resetDragState();
      return;
    }

    final _CurlSession session = _CurlSession(
      overlay: overlay,
      vsync: navigator,
      image: snapshot,
      devicePixelRatio: pixelRatio,
      edge: edge,
      options: options,
      backColor: back,
    );
    _session = session;
    _navigator = navigator;

    if (edge == CurlEdge.right) {
      // Forward: the next page goes in underneath the curling snapshot.
      navigator.push<void>(
        PageCurlRoute<void>(page: widget.nextPageBuilder!(context)),
      );
    } else {
      // Backward: hide this live page so the previous one (still painted
      // beneath a PageCurlRoute) shows through as the snapshot lifts.
      setState(() => _hidden = true);
    }
    session.show();
    options.sounds?.onPageTurn?.call();
    _applyDrag();
    if (_dragEnded) unawaited(_finishDrag());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragActive) return;
    final Offset? local = _toLocal(details.globalPosition);
    if (local == null) return;
    _dragX = local.dx;
    _applyDrag();
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragActive) return;
    _dragEnded = true;
    _endVelocity = details.velocity.pixelsPerSecond.dx;
    if (_session != null) unawaited(_finishDrag());
  }

  void _onDragCancel() {
    if (!_dragActive) return;
    _dragEnded = true;
    _endVelocity = 0.0;
    if (_session != null) unawaited(_finishDrag());
  }

  double _travel() {
    final double t = _dragEdge == CurlEdge.left
        ? _dragX - _dragStartX
        : _dragStartX - _dragX;
    return t < 0.0 ? 0.0 : t;
  }

  void _applyDrag() {
    final _CurlSession? session = _session;
    if (session == null) return;
    final double r = widget.options.rollRadius;
    final double tn = math.tan(_dragAngle).abs();
    // Distance the fold line can travel from start to gone.
    final double range = _dragWidth + _dragHeight * tn + r + 5.0;
    // The fold moves a bit more than half of the finger's travel, so the
    // lifted edge stays close to the finger.
    final double progress = (_travel() * 0.62 / range).clamp(0.0, 1.0).toDouble();
    session.pose.value = PageCurlPose(progress, _dragAngle);
  }

  Future<void> _finishDrag() async {
    final _CurlSession? session = _session;
    final NavigatorState? navigator = _navigator;
    if (session == null || navigator == null) return;
    _session = null;
    _navigator = null;

    final PageCurlOptions options = widget.options;
    final double directionVelocity =
    _dragEdge == CurlEdge.left ? _endVelocity : -_endVelocity;
    final bool commit = _travel() > options.completeThreshold * _dragWidth ||
        directionVelocity > options.flingVelocity;
    final double progress = session.pose.value.progress;
    final CurlEdge edge = _dragEdge;

    if (commit) {
      // Backward: reveal the previous page for real now.
      if (edge == CurlEdge.left) navigator.pop();
      final int ms = math.max(
        180,
        (options.duration.inMilliseconds * (1.0 - progress)).round(),
      );
      await session.animateTo(
        1.0,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOutCubic,
      );
    } else {
      final int ms = math.max(
        160,
        (options.duration.inMilliseconds * 0.5 * progress).round(),
      );
      await session.animateTo(
        0.0,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOut,
      );
      if (edge == CurlEdge.right) {
        navigator.pop(); // take the pushed page back out
      } else if (mounted) {
        setState(() => _hidden = false);
      }
    }
    session.dispose();
    _resetDragState();
  }

  void _resetDragState() {
    _dragActive = false;
    _dragEnded = false;
    _curlBusy = false;
  }

  Widget _edgeStrip(CurlEdge edge) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (DragStartDetails d) => _onDragStart(edge, d),
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final PageCurlOptions options = widget.options;
    final bool canForward = options.interactive && widget.nextPageBuilder != null;
    final bool canBack = options.interactive && _canDragBack(context);

    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Opacity(
          opacity: _hidden ? 0.0 : 1.0,
          child: RepaintBoundary(key: boundaryKey, child: widget.child),
        ),
        if (canForward)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: options.dragEdgeExtent,
            child: _edgeStrip(CurlEdge.right),
          ),
        if (canBack)
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: options.dragEdgeExtent,
            child: _edgeStrip(CurlEdge.left),
          ),
      ],
    );
  }
}

/// A ready-made "forward" icon button: turns to [page] with the page curl.
/// Put it anywhere inside a [FabricPageTurn] (e.g. AppBar actions).
class PageCurlForwardButton extends StatelessWidget {
  const PageCurlForwardButton({
    super.key,
    required this.page,
    this.options,
    this.icon = const Icon(Icons.arrow_forward),
    this.tooltip = 'Forward',
  });

  final Widget page;
  final PageCurlOptions? options;
  final Widget icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: () =>
          pushWithPageCurl<void>(context, page: page, options: options),
    );
  }
}

/// A ready-made "back" icon button: turns back with the page curl. Disabled
/// when there is no previous page.
class PageCurlBackwardButton extends StatelessWidget {
  const PageCurlBackwardButton({
    super.key,
    this.options,
    this.icon = const Icon(Icons.arrow_back),
    this.tooltip = 'Backward',
  });

  final PageCurlOptions? options;
  final Widget icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: Navigator.canPop(context)
          ? () => popWithPageCurl(context, options: options)
          : null,
    );
  }
}