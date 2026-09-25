# Fabric UI Animation

A 3D cloth physics simulation package for Flutter. Transform any rigid UI widget into a flexible, physical piece of fabric that you can grab, pull, stretch, and tear in real-time using Verlet integration and dynamic lighting!

## 🔗 Repository

* **GitHub:** [https://github.com/Jayeshkashyap2201/fabric_ui_animation](https://github.com/Jayeshkashyap2201/fabric_ui_animation)

## ✨ Features

* **3D Verlet Integration Physics:** Simulates nodes and springs for realistic cloth movement, gravity, and wrinkles.
* **Dynamic Lighting & Shading:** Calculates per-vertex normals for real-time 3D surface shading and shadows.
* **Tearing & Pinned Edges:** Pull hard to create natural holes, rips, and tension-based breaks in the cloth sheet.
* **Smooth Touch Interaction:** Smooth falloffs for natural dents and multi-node finger grabs.
* **Fabric Controller:** Programmatically trigger actions like peeling/releasing pins (`releasePins()`) or resetting (`reset()`).

## 🚀 Getting Started

Add this package to your project's `pubspec.yaml`:

```yaml
dependencies:
  fabric_ui_animation: ^1.0.0
```

## 💻 How to Use

Wrap any widget inside `FabricEffect` to bring it to life!

```dart
import 'package:flutter/material.dart';
import 'package:fabric_ui_animation/fabric_ui_animation.dart';

class FabricExample extends StatelessWidget {
  const FabricExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fabric UI Demo')),
      body: Center(
        child: FabricEffect(
          child: Container(
            width: 300,
            height: 400,
            color: Colors.deepPurple,
            child: const Center(
              child: Text(
                'Pull & Stretch Me!',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

## ⚠️ Important Notes

* **Opaque Background:** Ensure your wrapped child widget has an opaque background (e.g., using a solid color Container), otherwise transparent areas might appear during screen capture.
* **Scrollable Views:** If used inside scrollable elements, set `startOnLongProfile: true` (or `startOnLongPress: true`) to prevent pan gesture conflicts with vertical scrolling.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👨‍💻 Author / Developer

Developed with ❤️ by Jayesh Kashyap

* Email: jayeshkashyap2201@gmail.com
* GitHub: [https://github.com/Jayeshkashyap2201](https://github.com/Jayeshkashyap2201)