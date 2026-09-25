import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Which side the page curls away from - matching how a real book works:
/// turning forward lifts the right edge, turning back lifts the left edge.
enum CurlEdge { left, right }

/// Draws [image] as a page rolling up like paper around a vertical spine,
/// starting from [edge] and sweeping to the opposite side as [progress]
/// goes from 0.0 (flat, fully visible - nothing curled yet) to 1.0 (fully
/// rolled away and invisible, revealing whatever is underneath).
///
/// This is a parametric/geometric curl (a cylindrical roll), not a cloth
/// physics simulation - real paper-crush physics for a rigid, fast page
/// turn would be overkill and hard to keep looking crisp at speed. It
/// reuses the same two-pass textured-mesh + per-vertex lighting technique
/// as [FabricPainter] so the two effects feel consistent.
class PageCurlPainter extends CustomPainter {
  final ui.Image image;
  final double progress;
  final CurlEdge edge;
  final double devicePixelRatio;

  /// Radius of the paper roll, in logical pixels. Smaller = tighter curl.
  final double rollRadius;

  /// Horizontal resolution of the curl mesh. Higher = smoother curve.
  final int segments;

  PageCurlPainter({
    required this.image,
    required this.progress,
    required this.edge,
    this.devicePixelRatio = 1.0,
    this.rollRadius = 46.0,
    this.segments = 48,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    if (width <= 0 || height <= 0 || progress <= 0.0) return;

    final bool mirror = edge == CurlEdge.right;
    final double r = rollRadius;
    // Starts just past the far edge (fully flat) and sweeps until even the
    // starting edge has wrapped past pi (fully consumed/invisible).
    final double rollS = width - progress * (width + r * math.pi);

    final int cols = segments;
    final int vertexCount = (cols + 1) * 2; // a top+bottom row per column
    final Float32List positions = Float32List(vertexCount * 2);
    final Float32List uv = Float32List(vertexCount * 2);
    final Int32List colors = Int32List(vertexCount);
    final List<bool> visible = List<bool>.filled(vertexCount, true);

    for (int c = 0; c <= cols; c++) {
      final double xOriginal = width * c / cols;
      // Work in "distance from the starting edge" space so the same maths
      // handles both edges; un-mirror at the end.
      final double s = mirror ? (width - xOriginal) : xOriginal;
      final double d = s - rollS;

      double newS = s;
      int shadowAlpha = 0;
      int highlightAlpha = 0;
      bool vis = true;

      if (d > 0) {
        final double theta = d / r;
        if (theta > math.pi) {
          vis = false;
        } else {
          newS = rollS + r * math.sin(theta);
          if (theta <= math.pi / 2) {
            // Front of the page, darkening as it curves away from flat.
            shadowAlpha = (theta / (math.pi / 2) * 90).round().clamp(0, 255);
          } else {
            // The back of the sheet has rolled into view - fake a plain
            // paper backing by darkening it further (no real back texture).
            final double backT = (theta - math.pi / 2) / (math.pi / 2);
            shadowAlpha = (150 + backT * 80).round().clamp(0, 255);
          }
          // A soft bright crease right where the roll is tightest.
          final double crest =
              1.0 - ((theta - math.pi / 2).abs() / (math.pi / 2));
          if (crest > 0) {
            highlightAlpha = (crest * 255 * 0.45).round().clamp(0, 255);
          }
        }
      }

      final double newX = mirror ? (width - newS) : newS;
      final int rgb = highlightAlpha > shadowAlpha
          ? ((highlightAlpha << 24) | 0x00FFFFFF)
          : ((shadowAlpha << 24) | 0x00000000);

      for (int row = 0; row < 2; row++) {
        final int vi = c * 2 + row;
        final double y = row == 0 ? 0.0 : height;
        positions[vi * 2] = newX;
        positions[vi * 2 + 1] = y;
        uv[vi * 2] = xOriginal * devicePixelRatio;
        uv[vi * 2 + 1] = y * devicePixelRatio;
        colors[vi] = rgb;
        visible[vi] = vis;
      }
    }

    final List<int> indexList = <int>[];
    for (int c = 0; c < cols; c++) {
      final int tl = c * 2, bl = c * 2 + 1, tr = (c + 1) * 2, br = (c + 1) * 2 + 1;
      if (!visible[tl] || !visible[bl] || !visible[tr] || !visible[br]) continue;
      indexList
        ..add(tl)
        ..add(tr)
        ..add(bl)
        ..add(tr)
        ..add(br)
        ..add(bl);
    }
    if (indexList.isEmpty) return;
    final Uint16List indices = Uint16List.fromList(indexList);

    final Paint texturePaint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.medium
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
    final ui.Vertices textured = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uv,
      indices: indices,
    );
    canvas.drawVertices(textured, BlendMode.srcOver, texturePaint);

    final ui.Vertices shading = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(
      shading,
      BlendMode.modulate,
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFFFFFFFF),
    );

    // A soft drop shadow cast by the curling edge onto whatever is
    // underneath, drawn just ahead of the roll.
    if (progress < 1.0) {
      final double shadowX =
      mirror ? (width - (rollS - 1)) : (rollS - 1).clamp(0.0, width);
      final Rect shadowRect = mirror
          ? Rect.fromLTRB(shadowX - 18, 0, shadowX, height)
          : Rect.fromLTRB(shadowX, 0, shadowX + 18, height);
      final Gradient gradient = LinearGradient(
        begin: mirror ? Alignment.centerRight : Alignment.centerLeft,
        end: mirror ? Alignment.centerLeft : Alignment.centerRight,
        colors: const <Color>[Color(0x00000000), Color(0x33000000)],
      );
      canvas.drawRect(shadowRect, Paint()..shader = gradient.createShader(shadowRect));
    }
  }

  @override
  bool shouldRepaint(covariant PageCurlPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.image != image ||
        oldDelegate.edge != edge;
  }
}

Future<ui.Image> _captureFromKey(GlobalKey key, double pixelRatio) async {
  final RenderRepaintBoundary boundary =
  key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage(pixelRatio: pixelRatio);
}

Future<void> _runCurlOverlay(
    BuildContext context, {
      required ui.Image image,
      required double devicePixelRatio,
      required CurlEdge edge,
      required Duration duration,
      required Curve curve,
      required VoidCallback performNavigation,
    }) async {
  final OverlayState overlay = Overlay.of(context);
  final AnimationController controller = AnimationController(
    vsync: Navigator.of(context),
    duration: duration,
  );
  final Animation<double> curved = CurvedAnimation(parent: controller, curve: curve);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) {
      return IgnorePointer(
        child: AnimatedBuilder(
          animation: curved,
          builder: (BuildContext context, Widget? _) {
            return CustomPaint(
              size: Size.infinite,
              painter: PageCurlPainter(
                image: image,
                progress: curved.value,
                edge: edge,
                devicePixelRatio: devicePixelRatio,
              ),
            );
          },
        ),
      );
    },
  );

  overlay.insert(entry);
  // The navigation change happens instantly, hidden beneath the frozen
  // screenshot the overlay is currently showing at progress 0.
  performNavigation();

  await controller.forward();
  entry.remove();
  controller.dispose();
  image.dispose();
}

/// Pushes [page] instantly (no built-in route transition) and reveals it by
/// curling the current screen away from the right edge - like turning
/// forward to the next page in a book.
///
/// [pageKey] must be a [GlobalKey] on a [RepaintBoundary] wrapping the
/// **current** page's content (the page you're navigating away from) - it's
/// screenshotted right before the transition starts.
Future<T?> pushWithPageCurl<T>(
    BuildContext context, {
      required GlobalKey pageKey,
      required Widget page,
      Duration duration = const Duration(milliseconds: 500),
      Curve curve = Curves.easeInOutCubic,
    }) async {
  final double pixelRatio = View.of(context).devicePixelRatio;
  final ui.Image snapshot = await _captureFromKey(pageKey, pixelRatio);
  if (!context.mounted) {
    snapshot.dispose();
    return null;
  }

  T? result;
  await _runCurlOverlay(
    context,
    image: snapshot,
    devicePixelRatio: pixelRatio,
    edge: CurlEdge.right,
    duration: duration,
    curve: curve,
    performNavigation: () {
      Navigator.of(context)
          .push<T>(PageRouteBuilder<T>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => page,
      ))
          .then((T? value) => result = value);
    },
  );
  return result;
}

/// Pops the current page instantly, then curls its captured screenshot away
/// from the left edge - like turning back a page in a book - revealing the
/// previous page underneath (which never left the navigator stack).
///
/// [pageKey] must be a [GlobalKey] on a [RepaintBoundary] wrapping the
/// **current** (about to be popped) page's content.
Future<void> popWithPageCurl(
    BuildContext context, {
      required GlobalKey pageKey,
      Duration duration = const Duration(milliseconds: 500),
      Curve curve = Curves.easeInOutCubic,
    }) async {
  final double pixelRatio = View.of(context).devicePixelRatio;
  final ui.Image snapshot = await _captureFromKey(pageKey, pixelRatio);
  if (!context.mounted) {
    snapshot.dispose();
    return;
  }

  await _runCurlOverlay(
    context,
    image: snapshot,
    devicePixelRatio: pixelRatio,
    edge: CurlEdge.left,
    duration: duration,
    curve: curve,
    performNavigation: () => Navigator.of(context).pop(),
  );
}