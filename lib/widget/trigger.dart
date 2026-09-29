/// How a feature can be started directly by a gesture on `FabricEffect`,
/// without wiring any button or controller call.
///
/// Used by `CrumpleOptions.trigger` and `PinOptions.trigger`. A feature is
/// only ever gesture-triggered when its options object is actually passed to
/// the widget - passing none leaves the gesture free for your own use.
enum FabricTrigger {
  /// Never started by a gesture - only through the controller or a button.
  none,

  /// Press and hold on the widget.
  longPress,

  /// Double-tap on the widget.
  doubleTap,
}