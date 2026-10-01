# 🧵 Fabric UI Animation

A physics-based 3D fabric and cloth animation package for Flutter.

Transform ordinary Flutter widgets into interactive, physical surfaces that users can **grab, pull, stretch, crumple, tear, and turn** in real-time.

Built with **Verlet integration, spring-based physics, dynamic lighting, gesture interaction, and customizable animation effects**.

---

## ✨ Features

### 🧵 3D Cloth Physics

- Verlet integration based physics simulation
- Node and spring-based cloth structure
- Real-time fabric deformation
- Gravity and physical movement
- Natural wrinkles and surface deformation
- Configurable physics behavior

### ✋ Interactive Fabric

Interact with the fabric directly using touch gestures:

- Grab
- Pull
- Stretch
- Drag
- Crumple
- Release
- Tear

Smooth falloff calculations allow multiple nearby nodes to react naturally to finger interaction.

### ✂️ Tearing & Pin System

The fabric can dynamically respond to tension:

- Tension-based tearing
- Natural holes and ripped edges
- Pinned fabric edges
- Pin break interactions
- Programmatic pin release
- Fabric reset support

### 📄 Interactive Page Curl

Turn pages like a physical sheet of paper/fabric.

- Interactive page curl
- Gesture-based page turning
- Forward and backward page transitions
- Physics-based page deformation
- Configurable curl behavior
- Smooth page transitions

### 🧻 Crumple & Uncrumple

Create realistic fabric-like transitions with configurable crumpling:

- Crumple animation
- Uncrumple animation
- Adjustable crumple strength
- Twist
- Bunching
- Fade effects
- Custom animation duration

### 📱 Fabric Bottom Navigation

A custom bottom navigation experience with fabric-style transitions.

- Animated bottom navigation
- Fabric crumple effect
- Smooth page switching
- Physics-based transitions
- Active and inactive navigation states
- Customizable colors

### 💡 Dynamic Lighting & Shading

Give the fabric a physical 3D appearance using dynamic lighting.

- Per-vertex normal calculations
- Dynamic surface shading
- Shadows
- Highlights
- Glint effects
- Configurable lighting intensity

### 🔊 Sound Effects

Fabric interactions can be synchronized with custom sound effects.

Available callbacks include:

- `onGrab`
- `onTear`
- `onPinBreak`
- `onCrumple`
- `onPinsReleased`
- `onPageTurn`

This allows you to create a more immersive physical interaction.

### 🎛️ Customization

Customize the animation according to your UI:

- Animation duration
- Crumple strength
- Twist
- Bunching
- Fade fraction
- Shadow color
- Highlight color
- Shadow opacity
- Highlight opacity
- Glint strength
- Background color
- Active/inactive colors
- Physics transitions

---

# 🚀 Installation

Add `fabric_ui_animation` to your `pubspec.yaml`:

```yaml
dependencies:
  fabric_ui_animation: ^1.1.0