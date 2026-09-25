import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'physics.dart';

/// Colors for the light/shadow overlay that gives the cloth its 3D look.
/// The captured UI's own colors are untouched - this only tints folds and
/// the finger dent, so pick colors that read well against your app's
/// background. All fields have defaults, override only what you need.
class FabricTheme {
  /// Tint used where a fold faces away from the light.
  final Color shadowColor;

  /// Tint used where a fold catches the light.
  final Color highlightColor;

  /// Strongest possible shadow tint opacity (0..1).
  final double maxShadowOpacity;

  /// Strongest possible highlight tint opacity (0..1).
  final double maxHighlightOpacity;

  /// How much extra the specular glint (finger dent rim, sharp folds)
  /// adds on top of maxHighlightOpacity. 0 turns the glint off.
  final double specularStrength;

  const FabricTheme({
    this.shadowColor = const Color(0xFF000000),
    this.highlightColor = const Color(0xFFFFFFFF),
    this.maxShadowOpacity = 0.7,
    this.maxHighlightOpacity = 0.35,
    this.specularStrength = 0.4,
  });

  /// Default look, tuned for dark-themed screens (matches the reference
  /// video: black shadow, white highlight).
  static const FabricTheme dark = FabricTheme();

  /// Softer overlay for light-themed screens - a plain white highlight is
  /// almost invisible on a light background, so it leans more on shadow
  /// and uses a warm-grey highlight instead of pure white.
  static const FabricTheme light = FabricTheme(
    shadowColor: Color(0xFF000000),
    highlightColor: Color(0xFFFFE9C8),
    maxShadowOpacity: 0.55,
    maxHighlightOpacity: 0.22,
    specularStrength: 0.3,
  );

  factory FabricTheme.forBrightness(Brightness brightness) {
    return brightness == Brightness.light ? light : dark;
  }

  FabricTheme copyWith({
    Color? shadowColor,
    Color? highlightColor,
    double? maxShadowOpacity,
    double? maxHighlightOpacity,
    double? specularStrength,
  }) {
    return FabricTheme(
      shadowColor: shadowColor ?? this.shadowColor,
      highlightColor: highlightColor ?? this.highlightColor,
      maxShadowOpacity: maxShadowOpacity ?? this.maxShadowOpacity,
      maxHighlightOpacity: maxHighlightOpacity ?? this.maxHighlightOpacity,
      specularStrength: specularStrength ?? this.specularStrength,
    );
  }
}

/// Draws the captured UI on the cloth mesh (one draw call) and then a second
/// draw call with per-vertex light/shadow colours computed from the cloth
/// normals - that is what makes the folds and the finger dent look 3D.
class FabricPainter extends CustomPainter {
  final FabricSimulation simulation;
  final ui.Image capturedImage;
  final double devicePixelRatio;
  final FabricTheme theme;

  FabricPainter(
      this.simulation,
      this.capturedImage, {
        this.devicePixelRatio = 1.0,
        this.theme = const FabricTheme(),
        Listenable? repaint,
      }) : super(repaint: repaint);

  // Light comes from the top-left, in front of the screen (normalised).
  static const double _lightX = -0.3815;
  static const double _lightY = -0.5220;
  static const double _lightZ = 0.7629;
  // Half vector between the light and the viewer (0, 0, 1).
  static const double _halfX = -0.2032;
  static const double _halfY = -0.2780;
  static const double _halfZ = 0.9389;
  static final double _flatSpec = math.pow(_halfZ, 40).toDouble();

  // Mild perspective so bulging parts get slightly larger.
  static const double _focal = 1400.0;

  late final Float32List _texCoords = _buildTexCoords();

  late final Paint _texturePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.medium
    ..shader = ImageShader(
      capturedImage,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
    );

  // modulate is symmetric, so with an opaque white paint the result is
  // exactly the vertex colour regardless of source/destination order.
  late final Paint _shadePaint = Paint()
    ..isAntiAlias = false
    ..color = const Color(0xFFFFFFFF);

  Uint16List? _indices;
  int _indicesVersion = -1;

  Float32List _buildTexCoords() {
    // The image was captured at devicePixelRatio, so texture coordinates
    // must be in image pixels, not logical pixels.
    final List<PointMass> nodes = simulation.nodes;
    final Float32List coords = Float32List(nodes.length * 2);
    for (int i = 0; i < nodes.length; i++) {
      coords[i * 2] = nodes[i].originalX * devicePixelRatio;
      coords[i * 2 + 1] = nodes[i].originalY * devicePixelRatio;
    }
    return coords;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final FabricSimulation sim = simulation;
    final List<PointMass> nodes = sim.nodes;
    final int cols = sim.cols;
    final int rows = sim.rows;

    if (_indices == null || _indicesVersion != sim.topologyVersion) {
      _indices = sim.buildIndices();
      _indicesVersion = sim.topologyVersion;
    }
    final Uint16List indices = _indices!;
    if (indices.isEmpty) return;

    final Float32List positions = Float32List(nodes.length * 2);
    final Int32List colors = Int32List(nodes.length);
    final double cx = sim.width * 0.5;
    final double cy = sim.height * 0.5;
    final int shadowRGB = theme.shadowColor.value & 0x00FFFFFF;
    final int highlightRGB = theme.highlightColor.value & 0x00FFFFFF;
    final double maxShadow = theme.maxShadowOpacity;
    final double maxHighlight = theme.maxHighlightOpacity;
    bool shaded = false;

    for (int gy = 0; gy < rows; gy++) {
      final int up = gy > 0 ? gy - 1 : 0;
      final int down = gy < rows - 1 ? gy + 1 : rows - 1;

      for (int gx = 0; gx < cols; gx++) {
        final int i = gy * cols + gx;
        final PointMass node = nodes[i];

        // Projection.
        final double z = node.z.clamp(-400.0, 400.0).toDouble();
        final double scale = _focal / (_focal - z);
        positions[i * 2] = cx + (node.x - cx) * scale;
        positions[i * 2 + 1] = cy + (node.y - cy) * scale;

        // Surface normal from the neighbours (central differences).
        final PointMass l = nodes[gy * cols + (gx > 0 ? gx - 1 : 0)];
        final PointMass r = nodes[gy * cols + (gx < cols - 1 ? gx + 1 : cols - 1)];
        final PointMass u = nodes[up * cols + gx];
        final PointMass d = nodes[down * cols + gx];

        final double tx0 = r.x - l.x, tx1 = r.y - l.y, tx2 = r.z - l.z;
        final double ty0 = d.x - u.x, ty1 = d.y - u.y, ty2 = d.z - u.z;

        double nx = tx1 * ty2 - tx2 * ty1;
        double ny = tx2 * ty0 - tx0 * ty2;
        double nz = tx0 * ty1 - tx1 * ty0;
        final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-6) {
          nx = 0.0;
          ny = 0.0;
          nz = 1.0;
        } else {
          nx /= len;
          ny /= len;
          nz /= len;
        }
        if (nz < 0.0) {
          // Folded over: light the back side as well.
          nx = -nx;
          ny = -ny;
          nz = -nz;
        }

        // Lighting relative to the flat sheet, so an undisturbed sheet gets
        // exactly zero overlay and looks identical to the real widget.
        final double diffuse = nx * _lightX + ny * _lightY + nz * _lightZ;
        final double rel = (diffuse > 0.0 ? diffuse : 0.0) - _lightZ;

        double shadow = 0.0;
        double light = 0.0;
        if (rel < 0.0) {
          shadow = math.min(maxShadow, -rel * 1.25);
        } else {
          light = math.min(maxHighlight, rel * 0.75);
        }

        final double nh = nx * _halfX + ny * _halfY + nz * _halfZ;
        if (nh > 0.0 && theme.specularStrength > 0.0) {
          final double spec = math.pow(nh, 40).toDouble() - _flatSpec;
          if (spec > 0.0) {
            light = math.min(
              maxHighlight + theme.specularStrength * 0.25,
              light + spec * theme.specularStrength,
            );
          }
        }

        if (light > shadow) {
          final int a = (light * 255.0).round().clamp(0, 255);
          colors[i] = (a << 24) | highlightRGB;
          if (a > 0) shaded = true;
        } else {
          final int a = (shadow * 255.0).round().clamp(0, 255);
          colors[i] = (a << 24) | shadowRGB;
          if (a > 0) shaded = true;
        }
      }
    }

    // Pass 1: the captured UI mapped onto the cloth.
    final ui.Vertices textured = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: _texCoords,
      indices: indices,
    );
    canvas.drawVertices(textured, BlendMode.srcOver, _texturePaint);

    // Pass 2: light and shadow on top of it.
    if (shaded) {
      final ui.Vertices lighting = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      );
      canvas.drawVertices(lighting, BlendMode.modulate, _shadePaint);
    }
  }

  @override
  bool shouldRepaint(covariant FabricPainter oldDelegate) {
    return oldDelegate.simulation != simulation ||
        oldDelegate.capturedImage != capturedImage;
  }
}