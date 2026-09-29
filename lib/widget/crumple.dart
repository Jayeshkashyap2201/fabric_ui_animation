import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fabric_effect.dart' show FabricController;
import '../physics.dart';
import 'trigger.dart';

/// Settings for crushing the sheet toward a point, like paper being balled
/// up. Pass it once as `FabricEffect(crumple: CrumpleOptions(...))` to set
/// the default feel and to let the widget start a crumple by itself on a
/// gesture ([trigger]) - no button needed. Override per call with
/// `controller.crumple(options: ...)`.
class CrumpleOptions {
  /// Gesture on the widget that crumples it toward the touch point.
  /// [FabricTrigger.none] = only when you call `controller.crumple()` or
  /// use a [CrumpleButton].
  final FabricTrigger trigger;

  /// How long the crumple plays before it is fully gone.
  final Duration duration;

  /// Share of the remaining distance to the target closed per solver
  /// iteration. Higher = balls up faster / tighter.
  final double strength;

  /// Sideways twist while it collapses (0 = straight in, higher = scrunchier).
  final double twist;

  /// Depth bunching - gives the wad real volume instead of a flat dot.
  final double bunching;

  /// Fraction (0..1) of [duration], at the end, spent fading out.
  final double fadeFraction;

  /// If set, the widget grows back by itself this long after it vanished.
  /// Null = stays gone until `controller.reset()`.
  final Duration? autoResetAfter;

  /// Called once the crumple has finished (after the fade-out).
  final VoidCallback? onComplete;

  const CrumpleOptions({
    this.trigger = FabricTrigger.longPress,
    this.duration = const Duration(milliseconds: 500),
    this.strength = 0.07,
    this.twist = 0.35,
    this.bunching = 2.2,
    this.fadeFraction = 0.55,
    this.autoResetAfter,
    this.onComplete,
  });

  CrumpleOptions copyWith({
    FabricTrigger? trigger,
    Duration? duration,
    double? strength,
    double? twist,
    double? bunching,
    double? fadeFraction,
    Duration? autoResetAfter,
    VoidCallback? onComplete,
  }) {
    return CrumpleOptions(
      trigger: trigger ?? this.trigger,
      duration: duration ?? this.duration,
      strength: strength ?? this.strength,
      twist: twist ?? this.twist,
      bunching: bunching ?? this.bunching,
      fadeFraction: fadeFraction ?? this.fadeFraction,
      autoResetAfter: autoResetAfter ?? this.autoResetAfter,
      onComplete: onComplete ?? this.onComplete,
    );
  }
}

/// The crumple physics: pulls every node toward one point on top of the
/// springs (which resist and make the wrinkles), with a twist and a little
/// depth bunching. Keeps whatever tearing / dropped pins already happened.
class CrumpleForce extends SimulationForce {
  CrumpleForce({
    required this.targetX,
    required this.targetY,
    required this.options,
  });

  /// Target in the same local coordinates as the simulation.
  final double targetX;
  final double targetY;
  final CrumpleOptions options;

  bool _active = true;

  @override
  bool get isActive => _active;

  void stop() => _active = false;

  /// Frees the pins and makes gravity permanent, so the sheet never springs
  /// back flat. Call before adding the force to the simulation.
  void start(FabricSimulation sim) {
    sim.gravityOn = true;
    sim.endGrab();
    for (final PointMass node in sim.pinNodes) {
      node.isPinned = false;
      node.releaseIn = -1;
    }
  }

  @override
  void applyIteration(FabricSimulation sim) {
    final double k = options.strength;
    final double twistK = k * options.twist;

    for (final PointMass node in sim.nodes) {
      if (node.isPinned) continue;
      final double dx = targetX - node.x;
      final double dy = targetY - node.y;
      final double dist = math.sqrt(dx * dx + dy * dy) + 1e-3;

      node.x += dx * k;
      node.y += dy * k;

      // Tangential twist so it scrunches into a wad instead of collapsing
      // straight into a flat point.
      final double tangentialX = -dy / dist;
      final double tangentialY = dx / dist;
      final double twist = dist * twistK;
      node.x += tangentialX * twist;
      node.y += tangentialY * twist;
    }
  }

  @override
  void afterIterations(FabricSimulation sim) {
    for (final PointMass node in sim.nodes) {
      if (node.isPinned) continue;
      final double noise = _pseudoRandom(node.originalX, node.originalY);
      node.z += (0.3 + noise * 1.4) * options.bunching;
      node.z *= 0.985;
    }
  }

  static double _pseudoRandom(double x, double y) {
    final double s = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return s - s.floorToDouble();
  }
}

/// A ready-made button that crumples the [controller]'s widget toward
/// **itself** - nothing else to wire up.
class CrumpleButton extends StatefulWidget {
  const CrumpleButton({
    super.key,
    required this.controller,
    required this.child,
    this.options,
    this.style,
  });

  final FabricController controller;
  final Widget child;

  /// Overrides the widget's own `FabricEffect.crumple` options for this button.
  final CrumpleOptions? options;
  final ButtonStyle? style;

  @override
  State<CrumpleButton> createState() => _CrumpleButtonState();
}

class _CrumpleButtonState extends State<CrumpleButton> {
  final GlobalKey _buttonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: _buttonKey,
      style: widget.style,
      onPressed: () => widget.controller
          .crumple(options: widget.options, originKey: _buttonKey),
      child: widget.child,
    );
  }
}