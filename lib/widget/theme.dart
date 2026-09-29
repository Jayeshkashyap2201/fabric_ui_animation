import 'dart:ui' show Brightness, Color;

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
  /// and uses a warm highlight instead of pure white.
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