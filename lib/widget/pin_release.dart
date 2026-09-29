import 'package:flutter/material.dart';

import 'fabric_effect.dart' show FabricController;
import '../physics.dart';
import 'trigger.dart';

/// How the pins let go of the wall.
enum PinReleaseMode {
  /// One after another (bottom-right first) - the sheet peels off the wall.
  wave,

  /// Every pin on the same frame - the whole sheet drops at once.
  allAtOnce,
}

/// Settings for pulling the pins. Pass it once as
/// `FabricEffect(pins: PinOptions(...))` to set the default feel and to let
/// the widget release the pins by itself on a gesture ([trigger]). Override
/// per call with `controller.releasePins(options: ...)`.
class PinOptions {
  /// Gesture on the widget that releases the pins.
  /// [FabricTrigger.none] = only via the controller or a [PinsButton].
  final FabricTrigger trigger;

  /// [PinReleaseMode.wave] or [PinReleaseMode.allAtOnce].
  final PinReleaseMode mode;

  /// How spread out the wave is - shorter = pins let go closer together =
  /// a snappier drop. Ignored for [PinReleaseMode.allAtOnce].
  final Duration duration;

  /// If set, the widget comes back by itself this long after the cloth
  /// settled. Null = stays down until `controller.reset()`.
  final Duration? autoResetAfter;

  /// Called once the cloth has settled after the release.
  final VoidCallback? onComplete;

  const PinOptions({
    this.trigger = FabricTrigger.doubleTap,
    this.mode = PinReleaseMode.wave,
    this.duration = const Duration(milliseconds: 750),
    this.autoResetAfter,
    this.onComplete,
  });

  PinOptions copyWith({
    FabricTrigger? trigger,
    PinReleaseMode? mode,
    Duration? duration,
    Duration? autoResetAfter,
    VoidCallback? onComplete,
  }) {
    return PinOptions(
      trigger: trigger ?? this.trigger,
      mode: mode ?? this.mode,
      duration: duration ?? this.duration,
      autoResetAfter: autoResetAfter ?? this.autoResetAfter,
      onComplete: onComplete ?? this.onComplete,
    );
  }
}

/// Schedules and performs the pin release. Gravity switches on for good.
class PinReleaseForce extends SimulationForce {
  PinReleaseForce({required this.options, this.forceAllAtOnce = false});

  final PinOptions options;

  /// Release everything at once whatever `options.mode` says.
  final bool forceAllAtOnce;

  final List<PointMass> _scheduled = <PointMass>[];

  @override
  bool get isActive => _scheduled.isNotEmpty;

  /// Call once before adding the force to the simulation.
  void start(FabricSimulation sim) {
    sim.gravityOn = true;
    sim.endGrab();

    final bool all = forceAllAtOnce || options.mode == PinReleaseMode.allAtOnce;
    // ~60 steps/sec: turn the wave duration into a frame spread.
    final int spreadFrames =
    all ? 0 : (options.duration.inMilliseconds / (1000 / 60)).round().clamp(0, 600);

    for (final PointMass node in sim.pinNodes) {
      if (!node.isPinned) continue;
      if (all) {
        node.isPinned = false;
        node.releaseIn = -1;
        continue;
      }
      final double nx = node.originalX / sim.width;
      final double ny = node.originalY / sim.height;
      final double wave = ((1.0 - nx) + (1.0 - ny)) * 0.5;
      node.releaseIn = (wave * spreadFrames).round() + sim.random.nextInt(6);
      _scheduled.add(node);
    }

    // A little z noise so the falling sheet crumples instead of sliding.
    for (final PointMass node in sim.nodes) {
      if (node.isPinned) continue;
      node.oldZ = node.z - (sim.random.nextDouble() - 0.5) * 2.0;
    }
  }

  @override
  void beforeStep(FabricSimulation sim) {
    for (int i = _scheduled.length - 1; i >= 0; i--) {
      final PointMass node = _scheduled[i];
      if (node.releaseIn <= 0) {
        node.isPinned = false;
        node.releaseIn = -1;
        _scheduled.removeAt(i);
      } else {
        node.releaseIn--;
      }
    }
  }
}

/// A ready-made button that releases the pins of the [controller]'s widget.
/// [dropAll] true = every pin at once, false = the peeling wave.
class PinsButton extends StatelessWidget {
  const PinsButton({
    super.key,
    required this.controller,
    required this.child,
    this.options,
    this.dropAll = false,
    this.style,
  });

  final FabricController controller;
  final Widget child;

  /// Overrides the widget's own `FabricEffect.pins` options for this button.
  final PinOptions? options;
  final bool dropAll;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: style,
      onPressed: () => dropAll
          ? controller.dropAllPins(options: options)
          : controller.releasePins(options: options),
      child: child,
    );
  }
}