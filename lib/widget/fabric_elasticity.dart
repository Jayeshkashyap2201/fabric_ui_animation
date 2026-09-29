/// All the "stretchiness" knobs in one place. Pass a custom instance to
/// `FabricEffect(elasticity: ...)` to make the cloth feel softer/stiffer, or
/// use one of the presets below. All fields have sensible defaults, so you
/// only need to override what you want to change.
class FabricElasticity {
  /// Resistance of the grid edges to stretching. 1.0 = rigid-ish, lower =
  /// stretchier fabric (silk-like).
  final double structuralStiffness;

  /// Resistance to shearing (diagonal springs) - keeps squares from
  /// collapsing into slivers when pulled sideways.
  final double shearStiffness;

  /// Resistance to folding (springs that skip one node) - higher keeps the
  /// sheet flatter and less crumply.
  final double bendStiffness;

  /// Velocity damping per step. Closer to 1.0 = less energy lost, so the
  /// cloth swings/settles longer.
  final double damping;

  /// Extra damping only on the depth (z) axis.
  final double zDamping;

  /// How strongly gravity pulls once the cloth is released, in logical
  /// px/s^2. Higher = falls faster.
  final double gravity;

  /// Per-step speed cap, prevents the simulation exploding on a big jump.
  final double maxSpeed;

  /// How strongly an un-grabbed, un-torn node eases back to its resting
  /// x/y position every step (only while still pinned to the wall).
  final double homeXY;

  /// How strongly a node's depth relaxes back to flat every step.
  final double homeZ;

  /// How strongly a grabbed node is pulled toward the finger (0..1).
  /// Higher = fabric feels "stuck" to your finger; lower = more slippery.
  final double holdStrength;

  /// Constraint-solver iterations per step. Higher = stiffer, more
  /// accurate, more expensive.
  final int iterations;

  const FabricElasticity({
    this.structuralStiffness = 1.0,
    this.shearStiffness = 0.8,
    this.bendStiffness = 0.25,
    this.damping = 0.985,
    this.zDamping = 0.97,
    this.gravity = 4000.0,
    this.maxSpeed = 60.0,
    this.homeXY = 0.004,
    this.homeZ = 0.02,
    this.holdStrength = 0.5,
    this.iterations = 5,
  });

  /// Default feel used when nothing is specified - cotton-sheet-like.
  static const FabricElasticity standard = FabricElasticity();

  /// Loose, stretchy, silk-like cloth. Sags and jiggles more.
  static const FabricElasticity soft = FabricElasticity(
    structuralStiffness: 0.55,
    shearStiffness: 0.45,
    bendStiffness: 0.10,
    damping: 0.992,
    holdStrength: 0.38,
    iterations: 4,
  );

  /// Taut, canvas/denim-like cloth. Resists stretching, tears less easily.
  static const FabricElasticity stiff = FabricElasticity(
    structuralStiffness: 1.0,
    shearStiffness: 0.95,
    bendStiffness: 0.45,
    damping: 0.96,
    holdStrength: 0.68,
    iterations: 7,
  );

  FabricElasticity copyWith({
    double? structuralStiffness,
    double? shearStiffness,
    double? bendStiffness,
    double? damping,
    double? zDamping,
    double? gravity,
    double? maxSpeed,
    double? homeXY,
    double? homeZ,
    double? holdStrength,
    int? iterations,
  }) {
    return FabricElasticity(
      structuralStiffness: structuralStiffness ?? this.structuralStiffness,
      shearStiffness: shearStiffness ?? this.shearStiffness,
      bendStiffness: bendStiffness ?? this.bendStiffness,
      damping: damping ?? this.damping,
      zDamping: zDamping ?? this.zDamping,
      gravity: gravity ?? this.gravity,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      homeXY: homeXY ?? this.homeXY,
      homeZ: homeZ ?? this.homeZ,
      holdStrength: holdStrength ?? this.holdStrength,
      iterations: iterations ?? this.iterations,
    );
  }
}