import 'dart:ui' show VoidCallback;

/// Optional callbacks so you can trigger your own sound effects (or haptics)
/// at the right moments. All are null (silent) by default - wire up
/// whichever ones you want, e.g. with `audioplayers` or `SystemSound.play`.
class FabricSounds {
  /// A touch first grabs the cloth.
  final VoidCallback? onGrab;

  /// A spring tears (a hole/rip opens).
  final VoidCallback? onTear;

  /// A pin lets go of the wall.
  final VoidCallback? onPinBreak;

  /// The cloth has fully stopped moving after being torn / released.
  final VoidCallback? onSettle;

  /// A crumple starts.
  final VoidCallback? onCrumple;

  /// A pull-pins / drop-all-pins release starts.
  final VoidCallback? onPinsReleased;

  /// A page-curl turn starts (forward or backward).
  final VoidCallback? onPageTurn;

  const FabricSounds({
    this.onGrab,
    this.onTear,
    this.onPinBreak,
    this.onSettle,
    this.onCrumple,
    this.onPinsReleased,
    this.onPageTurn,
  });
}