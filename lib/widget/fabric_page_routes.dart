import 'package:flutter/material.dart';

/// A page route that feels like part of the fabric effect: the incoming page
/// scales up from a point and fades in when you go **forward**
/// (`Navigator.push`), and the exact same animation plays in reverse the
/// moment you go **backward** (`Navigator.pop`, or the system/edge-swipe back
/// gesture) - you don't need to wire anything extra for the backward case,
/// `PageRouteBuilder` runs the transition in reverse automatically on pop.
///
/// Usage:
/// ```dart
/// Navigator.push(context, FabricPageRoute(page: const NextPage()));
/// // ... later, anywhere (button, AppBar back arrow, swipe-back gesture):
/// Navigator.pop(context);
/// ```
///
/// [duration] controls the speed of both directions; pass different
/// [forwardCurve] / [backwardCurve] values for a different feel each way
/// (e.g. a snappier entrance than exit).
class FabricPageRoute<T> extends PageRouteBuilder<T> {
  FabricPageRoute({
    required Widget page,
    Duration duration = const Duration(milliseconds: 420),
    Curve forwardCurve = Curves.easeOutCubic,
    Curve backwardCurve = Curves.easeInCubic,
    bool opaque = true,
    super.settings,
  }) : super(
    opaque: opaque,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        ) =>
    page,
    transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
        ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: forwardCurve,
        reverseCurve: backwardCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}