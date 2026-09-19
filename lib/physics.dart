import 'dart:math' as math;
import 'dart:typed_data';

enum SpringKind { structural, shear, bend }

/// One node of the cloth. Simulated in 3D: x/y are screen axes,
/// z points towards the viewer (negative z = pushed into the screen).
class PointMass {
  double x;
  double y;
  double z;
  double oldX;
  double oldY;
  double oldZ;
  final double originalX;
  final double originalY;

  /// Attached to the "wall". Border nodes start pinned.
  bool isPinned;

  /// Frames until this pin lets go (-1 = not scheduled).
  int releaseIn = -1;

  /// Finger influence 0..1 and the node's offset from the finger.
  double hold = 0.0;
  double holdDx = 0.0;
  double holdDy = 0.0;

  /// Structural springs touching this node (used for pin-tension checks).
  final List<Spring> links = <Spring>[];

  PointMass(double px, double py, {this.isPinned = false})
      : x = px,
        y = py,
        z = 0.0,
        oldX = px,
        oldY = py,
        oldZ = 0.0,
        originalX = px,
        originalY = py;
}

class Spring {
  final PointMass p1;
  final PointMass p2;
  final double restingDistance;
  final double restSquared;
  final double stiffness;
  final SpringKind kind;

  /// Bend springs span two structural springs; they die when either does.
  final Spring? dependsOnA;
  final Spring? dependsOnB;

  bool isTorn = false;

  Spring(
      this.p1,
      this.p2, {
        this.stiffness = 1.0,
        this.kind = SpringKind.structural,
        this.dependsOnA,
        this.dependsOnB,
      })  : restingDistance = _restLength(p1, p2),
        restSquared = _restLength(p1, p2) * _restLength(p1, p2);

  static double _restLength(PointMass a, PointMass b) {
    final double dx = b.originalX - a.originalX;
    final double dy = b.originalY - a.originalY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// True when the spring is longer than [ratio] x its resting length.
  bool isOverstretched(double ratio) {
    final double dx = p2.x - p1.x;
    final double dy = p2.y - p1.y;
    final double dz = p2.z - p1.z;
    return dx * dx + dy * dy + dz * dz > restSquared * ratio * ratio;
  }

  void refreshDependencies() {
    if ((dependsOnA?.isTorn ?? false) || (dependsOnB?.isTorn ?? false)) {
      isTorn = true;
    }
  }

  void satisfy() {
    if (isTorn) return;

    final double dx = p2.x - p1.x;
    final double dy = p2.y - p1.y;
    final double dz = p2.z - p1.z;
    final double distance = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (distance < 1e-6) return;

    final double w1 = p1.isPinned ? 0.0 : 1.0;
    final double w2 = p2.isPinned ? 0.0 : 1.0;
    final double wSum = w1 + w2;
    if (wSum == 0.0) return;

    final double diff = (distance - restingDistance) / distance * stiffness;
    final double c1 = diff * w1 / wSum;
    final double c2 = diff * w2 / wSum;

    p1.x += dx * c1;
    p1.y += dy * c1;
    p1.z += dz * c1;
    p2.x -= dx * c2;
    p2.y -= dy * c2;
    p2.z -= dz * c2;
  }
}

class FabricSimulation {
  /// Fixed physics step (the widget runs this with an accumulator, so the
  /// feel is identical on 60 Hz and 120 Hz screens).
  static const double timeStep = 1.0 / 60.0;

  static const int _iterations = 5;
  static const double _damping = 0.985;
  static const double _zDamping = 0.97;
  static const double _gravity = 4000.0; // logical px / s^2
  static const double _maxSpeed = 60.0; // px per step
  static const double _homeXY = 0.004; // tiny pull back to the wall
  static const double _homeZ = 0.02; // flattens leftover wrinkles
  static const double _holdStrength = 0.5;

  final double width;
  final double height;
  final int cols;
  final int rows;

  /// A spring tears when stretched beyond this multiple of its rest length.
  final double tearRatio;

  /// A pin lets go when a spring attached to it is stretched beyond this.
  final double pinBreakRatio;

  final List<PointMass> nodes = <PointMass>[];
  final List<Spring> springs = <Spring>[];

  final List<Spring> _horizontal = <Spring>[]; // index: y * (cols - 1) + x
  final List<Spring> _vertical = <Spring>[]; // index: y * cols + x
  final List<Spring> _diagA = <Spring>[]; // top-left -> bottom-right
  final List<Spring> _diagB = <Spring>[]; // top-right -> bottom-left
  final List<Spring> _bend = <Spring>[];
  final List<PointMass> _pinNodes = <PointMass>[];
  final List<PointMass> _held = <PointMass>[];
  final math.Random _random = math.Random(7);

  /// Becomes true once anything tears / any pin lets go. From then on the
  /// cloth is affected by gravity and never returns to the flat state.
  bool gravityOn = false;

  /// Increments whenever a spring tears (painter rebuilds its triangles).
  int topologyVersion = 0;

  /// Average per-node movement of the last step (used to detect rest).
  double motion = 1.0;

  /// Largest distance of any visible node from its resting place.
  double maxOffset = 0.0;

  double _grabX = 0.0;
  double _grabY = 0.0;
  double _pushDepth = 0.0;

  FabricSimulation({
    required this.width,
    required this.height,
    required this.cols,
    required this.rows,
    this.tearRatio = 3.2,
    this.pinBreakRatio = 2.0,
  })  : assert(cols >= 3 && rows >= 3),
        assert(cols * rows <= 65535) {
    _generateGrid();
  }

  bool get isGrabbing => _held.isNotEmpty;

  void _generateGrid() {
    final double spacingX = width / (cols - 1);
    final double spacingY = height / (rows - 1);

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final bool border = y == 0 || y == rows - 1 || x == 0 || x == cols - 1;
        final PointMass node =
        PointMass(x * spacingX, y * spacingY, isPinned: border);
        nodes.add(node);
        if (border) _pinNodes.add(node);
      }
    }

    PointMass at(int x, int y) => nodes[y * cols + x];

    Spring register(Spring spring) {
      springs.add(spring);
      if (spring.kind == SpringKind.structural) {
        spring.p1.links.add(spring);
        spring.p2.links.add(spring);
      }
      return spring;
    }

    // Structural springs.
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        if (x < cols - 1) {
          _horizontal.add(register(Spring(at(x, y), at(x + 1, y))));
        }
        if (y < rows - 1) {
          _vertical.add(register(Spring(at(x, y), at(x, y + 1))));
        }
      }
    }

    // Shear springs (both diagonals of every cell).
    for (int y = 0; y < rows - 1; y++) {
      for (int x = 0; x < cols - 1; x++) {
        _diagA.add(register(Spring(at(x, y), at(x + 1, y + 1),
            stiffness: 0.8, kind: SpringKind.shear)));
        _diagB.add(register(Spring(at(x + 1, y), at(x, y + 1),
            stiffness: 0.8, kind: SpringKind.shear)));
      }
    }

    // Bend springs (skip one node) - resist folding, keep the sheet flat.
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        if (x < cols - 2) {
          _bend.add(register(Spring(
            at(x, y),
            at(x + 2, y),
            stiffness: 0.25,
            kind: SpringKind.bend,
            dependsOnA: _horizontal[y * (cols - 1) + x],
            dependsOnB: _horizontal[y * (cols - 1) + x + 1],
          )));
        }
        if (y < rows - 2) {
          _bend.add(register(Spring(
            at(x, y),
            at(x, y + 2),
            stiffness: 0.25,
            kind: SpringKind.bend,
            dependsOnA: _vertical[y * cols + x],
            dependsOnB: _vertical[(y + 1) * cols + x],
          )));
        }
      }
    }
  }

  // ---------------------------------------------------------------- finger

  /// Grabs every free node around ([x], [y]) with a smooth falloff.
  /// Returns false if nothing could be grabbed.
  bool beginGrab(
      double x,
      double y, {
        required double radius,
        required double pushDepth,
      }) {
    endGrab();
    _grabX = x;
    _grabY = y;
    _pushDepth = pushDepth;

    for (final PointMass node in nodes) {
      if (node.isPinned) continue;
      final double dx = node.x - x;
      final double dy = node.y - y;
      final double distance = math.sqrt(dx * dx + dy * dy);
      if (distance >= radius) continue;
      final double t = 1.0 - distance / radius;
      node.hold = t * t * (3.0 - 2.0 * t); // smoothstep
      node.holdDx = dx;
      node.holdDy = dy;
      _held.add(node);
    }
    return _held.isNotEmpty;
  }

  void moveGrab(double x, double y) {
    _grabX = x;
    _grabY = y;
  }

  void endGrab() {
    for (final PointMass node in _held) {
      node.hold = 0.0;
    }
    _held.clear();
  }

  void _applyGrab() {
    for (final PointMass node in _held) {
      if (node.isPinned) continue;
      final double k = node.hold * _holdStrength;
      node.x += (_grabX + node.holdDx - node.x) * k;
      node.y += (_grabY + node.holdDy - node.y) * k;
      node.z += (-_pushDepth * node.hold - node.z) * k;
    }
  }

  // ------------------------------------------------------------- pin release

  /// "Pull the pins": the pins let go one after another, starting from the
  /// bottom-right corner, so the sheet peels off the wall and falls.
  void releasePins({int spreadFrames = 45}) {
    gravityOn = true;
    endGrab();
    for (final PointMass node in _pinNodes) {
      if (!node.isPinned) continue;
      final double nx = node.originalX / width;
      final double ny = node.originalY / height;
      final double wave = ((1.0 - nx) + (1.0 - ny)) * 0.5;
      node.releaseIn = (wave * spreadFrames).round() + _random.nextInt(6);
    }
    // A little z noise so the falling sheet crumples instead of sliding.
    for (final PointMass node in nodes) {
      if (node.isPinned) continue;
      node.oldZ = node.z - (_random.nextDouble() - 0.5) * 2.0;
    }
  }

  void _processScheduledReleases() {
    for (final PointMass node in _pinNodes) {
      if (node.releaseIn < 0) continue;
      if (node.releaseIn == 0) {
        node.isPinned = false;
        node.releaseIn = -1;
      } else {
        node.releaseIn--;
      }
    }
  }

  // ------------------------------------------------------------------- step

  void step() {
    _processScheduledReleases();
    _integrate();

    final int count = springs.length;
    for (int it = 0; it < _iterations; it++) {
      for (int i = 0; i < count; i++) {
        springs[i].satisfy();
      }
      _applyGrab();
    }

    _breakOverstretched();
    _measureMotion();
  }

  void _integrate() {
    final double g = gravityOn ? _gravity * timeStep * timeStep : 0.0;

    for (final PointMass node in nodes) {
      if (node.isPinned) continue;

      double vx = (node.x - node.oldX) * _damping;
      double vy = (node.y - node.oldY) * _damping;
      double vz = (node.z - node.oldZ) * _damping * _zDamping;

      final double speed = math.sqrt(vx * vx + vy * vy + vz * vz);
      if (speed > _maxSpeed) {
        final double f = _maxSpeed / speed;
        vx *= f;
        vy *= f;
        vz *= f;
      }

      node.oldX = node.x;
      node.oldY = node.y;
      node.oldZ = node.z;

      node.x += vx;
      node.y += vy + g;
      node.z += vz;

      if (node.hold == 0.0) {
        if (!gravityOn) {
          node.x += (node.originalX - node.x) * _homeXY;
          node.y += (node.originalY - node.y) * _homeXY;
        }
        node.z -= node.z * _homeZ;
      }
    }
  }

  void _breakOverstretched() {
    bool changed = false;
    bool torn = false;

    // Pins go first: peeling from the wall happens before the cloth rips.
    for (final PointMass node in _pinNodes) {
      if (!node.isPinned || node.releaseIn >= 0) continue;
      for (final Spring spring in node.links) {
        if (!spring.isTorn && spring.isOverstretched(pinBreakRatio)) {
          node.isPinned = false;
          changed = true;
          break;
        }
      }
    }

    for (final Spring spring in springs) {
      if (spring.isTorn || spring.kind == SpringKind.bend) continue;
      if (spring.isOverstretched(tearRatio)) {
        spring.isTorn = true;
        changed = true;
        torn = true;
      }
    }

    if (torn) {
      for (final Spring spring in _bend) {
        spring.refreshDependencies();
      }
      topologyVersion++;
    }
    if (changed) gravityOn = true;
  }

  void _measureMotion() {
    final double limit = height + 300.0;
    double sum = 0.0;
    double maxOff = 0.0;
    int counted = 0;

    for (final PointMass node in nodes) {
      if (node.y > limit) continue; // fell out of view, ignore
      sum += (node.x - node.oldX).abs() +
          (node.y - node.oldY).abs() +
          (node.z - node.oldZ).abs();
      final double dx = node.x - node.originalX;
      final double dy = node.y - node.originalY;
      final double off = math.sqrt(dx * dx + dy * dy + node.z * node.z);
      if (off > maxOff) maxOff = off;
      counted++;
    }

    motion = counted == 0 ? 0.0 : sum / counted;
    maxOffset = maxOff;
  }

  // -------------------------------------------------------------- rendering

  /// Triangle indices; triangles that touch a torn spring are left out,
  /// which is what opens the holes / rips.
  Uint16List buildIndices() {
    final Uint16List buffer = Uint16List((rows - 1) * (cols - 1) * 6);
    int n = 0;

    for (int y = 0; y < rows - 1; y++) {
      for (int x = 0; x < cols - 1; x++) {
        final int cell = y * (cols - 1) + x;
        final int tl = y * cols + x;
        final int tr = tl + 1;
        final int bl = tl + cols;
        final int br = bl + 1;

        final bool diagOk = !_diagB[cell].isTorn;

        // Triangle 1: top edge, left edge, diagonal.
        if (diagOk &&
            !_horizontal[cell].isTorn &&
            !_vertical[y * cols + x].isTorn) {
          buffer[n++] = tl;
          buffer[n++] = tr;
          buffer[n++] = bl;
        }
        // Triangle 2: right edge, bottom edge, diagonal.
        if (diagOk &&
            !_vertical[y * cols + x + 1].isTorn &&
            !_horizontal[(y + 1) * (cols - 1) + x].isTorn) {
          buffer[n++] = tr;
          buffer[n++] = br;
          buffer[n++] = bl;
        }
      }
    }
    return buffer.sublist(0, n);
  }
}