import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Tiny sound-effect helper for the fabric demo.
///
/// Files live in `assets/sounds/` (declared in pubspec.yaml). Names passed
/// to [play] are relative to that folder, e.g. `Sfx.play('grab.mp3')`.
///
/// Every failure is printed with the prefix "[Sfx]" so you can see in the
/// console exactly what is wrong (missing asset, bad file, ...).
class Sfx {
  Sfx._();

  static const List<String> files = <String>[
    'grab.mp3',
    'tear.mp3',
    'pin.mp3',
    'pins_released.mp3',
    'crumple.mp3',
    'page.mp3',
  ];

  /// Master switch - flip it from a settings toggle.
  static bool enabled = true;

  /// 0.0 .. 1.0
  static double volume = 1.0;

  static final Map<String, DateTime> _lastPlayed = <String, DateTime>{};

  /// Call once before runApp (after WidgetsFlutterBinding.ensureInitialized).
  /// Copies the assets into the audio cache so the first play has no lag,
  /// and reports any asset that cannot be found.
  static Future<void> preload() async {
    for (final String file in files) {
      try {
        await AudioCache.instance.load(file);
        debugPrint('[Sfx] loaded $file');
      } catch (e) {
        debugPrint('[Sfx] CANNOT LOAD assets/$file -> $e');
      }
    }
  }

  /// Plays [file]. [minGapMs] ignores calls that come sooner than that after
  /// the previous play of the same file (for bursty events like tearing).
  static Future<void> play(String file, {int minGapMs = 0}) async {
    if (!enabled) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastPlayed[file];
    if (last != null && now.difference(last).inMilliseconds < minGapMs) return;
    _lastPlayed[file] = now;

    try {
      // A fresh player per play: overlapping sounds work and nothing can get
      // stuck in a stopped state. It frees itself when the sound ends.
      final AudioPlayer player = AudioPlayer();
      player.onPlayerComplete.first.then((_) => player.dispose());
      await player.setVolume(volume);
      await player.play(AssetSource(file));
      debugPrint('[Sfx] play $file');
    } catch (e) {
      debugPrint('[Sfx] play FAILED for $file -> $e');
    }
  }
}