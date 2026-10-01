import 'package:fabric_ui_animation/fabric_ui_animation.dart';
import 'package:flutter/material.dart';

import 'sfx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Sfx.preload();
  runApp(const MyApp());
}

/// One shared set of sound hooks for the whole app.
///
/// The `minGapMs` values stop bursty events (many springs tearing or many
/// pins breaking in the same moment) from stacking into one loud blast.
final FabricSounds appSounds = FabricSounds(
  onGrab: () => Sfx.play('grab.mp3', minGapMs: 200),
  onTear: () => Sfx.play('tear.mp3', minGapMs: 150),
  onPinBreak: () => Sfx.play('pin.mp3', minGapMs: 100),
  onCrumple: () => Sfx.play('crumple.mp3'),
  onPinsReleased: () => Sfx.play('pins_released.mp3'),
  onPageTurn: () => Sfx.play('page.mp3'),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fabric UI Demo',
      debugShowCheckedModeBanner: false,

      // Light and clean theme
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F8CFF),
          brightness: Brightness.light,
        ),

        scaffoldBackgroundColor: const Color(0xFFF7F9FC),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1F2937),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      home: const HomeShell(),
    );
  }
}

/// Hosts the bottom bar and the full-screen page curl.
///
/// The FabricPageTurn is intentionally above FabricBottomBar so the curl
/// animation gets the full available screen size.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _physicsTransition = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FabricPageTurn(
        // Not const any more because of `sounds`.
        options: PageCurlOptions(interactive: true, sounds: appSounds),

        // Full-screen page curl
        nextPageBuilder: (BuildContext context) => const _DetailsPage(),

        child: FabricBottomBar(
          physicsTransition: _physicsTransition,

          // Bottom bar has no `sounds` parameter yet, so play from here:
          // crumple sound when the cloth transition runs, a soft one for
          // the plain bounce-pop fallback.
          onIndexChanged: (int _) => Sfx.play(
            _physicsTransition ? 'crumple.mp3' : 'grab.mp3',
          ),

          // ---------------------------------------------------------------
          // LIGHT / SUBTLE CRUMPLE EFFECT
          // ---------------------------------------------------------------
          crumpleOptions: const CrumpleOptions(
            duration: Duration(milliseconds: 450),
            strength: 0.35,
            twist: 0.15,
            bunching: 0.15,
            fadeFraction: 0.35,
          ),

          uncrumpleOptions: const UncrumpleOptions(
            duration: Duration(milliseconds: 550),
          ),

          // Soft fold shading
          shadowColor: const Color(0xFFB8C1CC),
          highlightColor: Colors.white,

          shadowOpacity: 0.07,
          highlightOpacity: 0.05,
          glintStrength: 0.02,

          items: const <FabricBottomBarItem>[
            FabricBottomBarItem(icon: Icons.home_rounded, label: 'Home'),
            FabricBottomBarItem(icon: Icons.search_rounded, label: 'Search'),
            FabricBottomBarItem(icon: Icons.person_rounded, label: 'Profile'),
          ],

          pages: <Widget>[
            _HomePage(
              physicsTransition: _physicsTransition,
              onPhysicsTransitionChanged: (bool value) {
                setState(() {
                  _physicsTransition = value;
                });
              },
            ),

            const _PlaceholderPage(
              color: Color(0xFFEFF6FF),
              icon: Icons.search_rounded,
              title: 'Search',
            ),

            const _PlaceholderPage(
              color: Color(0xFFF0FDF4),
              icon: Icons.person_rounded,
              title: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Home tab.
///
/// FabricPageTurn is NOT placed here anymore.
/// It is handled by HomeShell so the page-curl overlay gets the full screen.
class _HomePage extends StatefulWidget {
  const _HomePage({
    required this.physicsTransition,
    required this.onPhysicsTransitionChanged,
  });

  final bool physicsTransition;
  final ValueChanged<bool> onPhysicsTransitionChanged;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final FabricController _controller = FabricController();
  final GlobalKey _shrinkButtonKey = GlobalKey();

  int _counter = 0;

  void _goForward() {
    // Uses the options (and sounds) of the FabricPageTurn in HomeShell.
    pushWithPageCurl<void>(context, page: const _DetailsPage());
  }

  @override
  Widget build(BuildContext context) {
    // Material instead of Container(color: ...)
    // so SwitchListTile's ink/splash remains visible correctly.
    return Material(
      color: const Color(0xFFF7F9FC),

      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Home',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),

                  // Backward page curl
                  const PageCurlBackwardButton(),

                  // Forward page curl
                  IconButton(
                    tooltip: 'Forward',
                    icon: const Icon(
                      Icons.arrow_forward,
                      color: Color(0xFF3B82F6),
                    ),
                    onPressed: _goForward,
                  ),
                ],
              ),
            ),

            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('Bottom bar crumple/uncrumple'),
              subtitle: const Text('Off = soft bounce pop instead'),
              value: widget.physicsTransition,
              onChanged: widget.onPhysicsTransitionChanged,
            ),

            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('Sound effects'),
              value: Sfx.enabled,
              onChanged: (bool value) {
                setState(() => Sfx.enabled = value);
              },
            ),

            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      FabricEffect(
                        controller: _controller,
                        sounds: appSounds,

                        crumple: const CrumpleOptions(),
                        pins: const PinOptions(),

                        child: Container(
                          width: 300,
                          height: 360,
                          padding: const EdgeInsets.all(20),

                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(24),

                            border: Border.all(
                              color: const Color(0xFFBFDBFE),
                              width: 1.5,
                            ),

                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 15,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),

                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              const Icon(
                                Icons.grain,
                                size: 56,
                                color: Color(0xFF3B82F6),
                              ),

                              const SizedBox(height: 14),

                              const Text(
                                'Pull & Stretch Me!',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                ),
                              ),

                              const SizedBox(height: 8),

                              const Text(
                                'Drag to stretch. Long-press to crumple. '
                                    'Double-tap to drop the pins.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),

                              const SizedBox(height: 20),

                              Text(
                                'Button pushed:',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),

                              Text(
                                '$_counter',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          PinsButton(
                            controller: _controller,
                            child: const Text('PULL THE PINS'),
                          ),

                          PinsButton(
                            controller: _controller,
                            dropAll: true,
                            child: const Text('DROP ALL PINS'),
                          ),

                          CrumpleButton(
                            key: _shrinkButtonKey,
                            controller: _controller,
                            child: const Text('CRUMPLE'),
                          ),

                          FilledButton(
                            onPressed: _controller.reset,
                            child: const Text('RESET'),
                          ),

                          FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                _counter++;
                              });
                            },
                            child: const Text('+1'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Details screen reached via forward page curl.
///
/// This page keeps its own FabricPageTurn so the backward arrow,
/// edge drag and system back gesture can curl back correctly.
class _DetailsPage extends StatelessWidget {
  const _DetailsPage();

  @override
  Widget build(BuildContext context) {
    return FabricPageTurn(
      // Same sounds here so turning BACK also plays the page sound.
      options: PageCurlOptions(sounds: appSounds),

      child: Material(
        color: const Color(0xFFF7F9FC),

        child: SafeArea(
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),

                child: Row(
                  children: <Widget>[
                    PageCurlBackwardButton(),

                    SizedBox(width: 8),

                    Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),

              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),

                    child: Text(
                      'Reached by turning forward from Home.\n'
                          'Turn back with the arrow, an edge drag,\n'
                          'or the system back gesture/button.',

                      textAlign: TextAlign.center,

                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.color,
    required this.icon,
    required this.title,
  });

  final Color color;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.center,

      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 64, color: const Color(0xFF334155)),

          const SizedBox(height: 12),

          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}