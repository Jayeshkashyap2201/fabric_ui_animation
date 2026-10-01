import 'dart:math' as math;

import '../physics.dart';

/// Settings for the "uncrumple" reveal - the reverse of [CrumpleOptions]:
/// the sheet starts as a crumpled ball and unfolds into place with real
/// physics (springs resisting, wrinkles straightening out as it goes).
class UncrumpleOptions {
  /// How long the whole unfold takes.
  final Duration duration;

  /// Share of the remaining distance back to each node's original position
  /// closed per solver iteration. Higher = unfolds faster.
  final double strength;

  /// Jitter radius (logical px) of the initial crumpled ball.
  final double startSpread;

  /// How deep (z) the initial crumpled ball bunches up.
  final double startBunch;

  const UncrumpleOptions({
    this.duration = const Duration(milliseconds: 700),
    this.strength = 0.05,
    this.startSpread = 10.0,
    this.startBunch = 60.0,
  });

  UncrumpleOptions copyWith({
    Duration? duration,
    double? strength,
    double? startSpread,
    double? startBunch,
  }) {
    return UncrumpleOptions(
      duration: duration ?? this.duration,
      strength: strength ?? this.strength,
      startSpread: startSpread ?? this.startSpread,
      startBunch: startBunch ?? this.startBunch,
    );
  }
}

/// The unfolding physics: every node eases back toward its own original
/// position (instead of toward one shared point, like [CrumpleForce] does)
/// every solver iteration. Springs still resist, so the sheet doesn't just
/// snap flat - it wrinkles and straightens out on the way, exactly like
/// paper being uncrumpled.
class UncrumpleForce extends SimulationForce {
  UncrumpleForce({required this.options});

  final UncrumpleOptions options;

  bool _active = true;

  @override
  bool get isActive => _active;

  void stop() => _active = false;

  /// Puts the sheet into a crumpled-ball starting shape at ([originX],
  /// [originY]) and frees the pins, so there's somewhere real to unfold
  /// FROM. Call once, right after creating the [FabricSimulation] and
  /// before adding this force with [FabricSimulation.addForce].
  void seedAndStart(FabricSimulation sim, double originX, double originY) {
    sim.gravityOn = false; // no falling - just spring/force driven unfolding
    sim.endGrab();
    for (final PointMass node in sim.pinNodes) {
      node.isPinned = false;
      node.releaseIn = -1;
    }
    for (final PointMass node in sim.nodes) {
      final double jx = (sim.random.nextDouble() - 0.5) * 2 * options.startSpread;
      final double jy = (sim.random.nextDouble() - 0.5) * 2 * options.startSpread;
      final double jz = sim.random.nextDouble() * options.startBunch;
      node.x = originX + jx;
      node.y = originY + jy;
      node.z = jz;
      // Zero initial velocity, so the first step doesn't explode.
      node.oldX = node.x;
      node.oldY = node.y;
      node.oldZ = node.z;
    }
  }

  @override
  void applyIteration(FabricSimulation sim) {
    final double k = options.strength;
    final double zk = math.min(1.0, k * 1.4);
    for (final PointMass node in sim.nodes) {
      if (node.isPinned) continue;
      node.x += (node.originalX - node.x) * k;
      node.y += (node.originalY - node.y) * k;
      node.z -= node.z * zk;
    }
  }
}