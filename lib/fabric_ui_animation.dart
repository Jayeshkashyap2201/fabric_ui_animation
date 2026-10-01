/// Fabric UI Animation
///
/// Wrap any widget in `FabricEffect` to make it behave like cloth - grab,
/// stretch, tear, crumple, pull its pins - and wrap a page in
/// `FabricPageTurn` to turn pages like a book. Every behaviour lives in its
/// own file and is configured with its own options class:
///
///  * widget/fabric_elasticity.dart - [FabricElasticity] (stretchiness)
///  * widget/theme.dart             - [FabricTheme]      (shadow / highlight colours)
///  * widget/fabric_sounds.dart     - [FabricSounds]     (sound / haptic hooks)
///  * widget/crumple.dart           - [CrumpleOptions], [CrumpleButton]
///  * widget/uncrumple.dart         - [UncrumpleOptions] (crumple's reverse - a real physics unfold)
///  * widget/pin_release.dart       - [PinOptions], [PinsButton]
///  * widget/page_curl.dart         - [PageCurlOptions], [FabricPageTurn], page-curl buttons
///  * widget/fabric_bottom_bar.dart - [FabricBottomBar], [FabricBottomBarItem] (crumple/uncrumple tab switcher)
///  * widget/fabric_effect.dart     - [FabricEffect], [FabricController]
///  * physics.dart                  - [FabricSimulation] (the cloth solver)
///  * fabric_painter.dart           - [FabricPainter] (renders the cloth)
///
/// A single import is all you need:
/// `import 'package:fabric_ui_animation/fabric_ui_animation.dart';`
library;

export 'fabric_painter.dart';
export 'physics.dart';
export 'widget/crumple.dart';
export 'widget/fabric_bottom_bar.dart';
export 'widget/fabric_effect.dart';
export 'widget/fabric_elasticity.dart';
export 'widget/fabric_sounds.dart';
export 'widget/page_curl.dart';
export 'widget/pin_release.dart';
export 'widget/theme.dart';
export 'widget/trigger.dart';
export 'widget/uncrumple.dart';