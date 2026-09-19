import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fabric_ui_animation/fabric_ui_animation.dart';

void main() {
  test('FabricEffect can be created', () {
    const effect = FabricEffect(
      child: SizedBox(
        width: 100,
        height: 100,
      ),
    );

    expect(effect, isA<FabricEffect>());
  });
}