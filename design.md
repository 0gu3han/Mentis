# Design System Strategy: Digital Zen & Spatial Intent

## 1. Overview & Creative North Star: "The Celestial Atheneum"
This design system is built to transform a standard web interface into a series of "Learning Rooms." The Creative North Star is **The Celestial Atheneum**: an environment that feels expansive yet focused, moving away from the cluttered, "flat" web toward a volumetric, spatial experience.

To break the "template" look, we reject rigid grids in favor of **Intentional Asymmetry**. Large-scale typography (Space Grotesk) acts as an architectural anchor, while content modules float with a sense of weightlessness. We use overlapping elements—where a "Glass" card might partially obscure a background gradient—to create a sense of true physical depth and "spatial awareness."

---

## 2. Colors & The Surface Philosophy
The palette transitions from the deep void of Indigo to the life-breath of Soft Teal.

### The "No-Line" Rule
**Borders are strictly prohibited for sectioning.** To define a new area, use a background shift. For example, a sidebar should not have a 1px line; it should simply transition from `surface` (#10141a) to `surface_container_low` (#181c22).

### Surface Hierarchy & Nesting
Treat the UI as a series of nested architectural layers:
- **The Base (Environment):** `surface` (#10141a).
- **The Floor (Primary Content Area):** `surface_container` (#1c2026).
- **The Pedestal (Active Cards/Modals):** `surface_container_high` (#262a31).
- **The Focus (Tooltips/Popovers):** `surface_container_highest` (#31353c).

### The "Glass & Gradient" Rule
Floating elements must utilize **Glassmorphism**. Combine `surface_variant` (#31353c) at 60% opacity with a `backdrop-blur` of 12px-20px.
**Signature Texture:** Use a subtle linear gradient for primary CTAs: `primary` (#666fca) to `primary_container` (#0d2187) at a 135-degree angle. This gives buttons a "lit from within" glow.

---

## 3. Typography: Editorial Authority
We pair the technical precision of **Inter** with the futuristic, wide-set personality of **Space Grotesk**.

- **Display & Headlines (Space Grotesk):** These are your "Architectural Markers." Use `display-lg` (3.5rem) with tight letter-spacing (-0.02em) to create a bold, editorial feel.
- **Titles & Body (Inter):** Inter provides the "Human Element." Use `title-md` (1.125rem) for sub-headers to ensure high readability during long learning sessions.
- **Labels (Inter):** Use `label-md` (0.75rem) in All Caps with +0.05em tracking for metadata, creating a "instrument panel" aesthetic.

---

## 4. Elevation & Depth: Tonal Layering
In a spatial learning app, "Up" is defined by light and clarity, not just shadows.

- **The Layering Principle:** Instead of a drop shadow, place a `surface_container_lowest` (#0a0e14) card inside a `surface_container` (#1c2026) section. The slight "dip" in value creates a natural inset look.
- **Ambient Shadows:** For floating elements (like a "Learning Orb" or Modal), use a diffused shadow: `0px 24px 48px rgba(14, 34, 136, 0.15)`. Note the use of the `on_primary` tint in the shadow to mimic the indigo environment.
- **The "Ghost Border" Fallback:** If a container is lost against a similar background, apply a 1px stroke using `outline_variant` (#454652) at **15% opacity**. It should be felt, not seen.
- **Spatial Focus:** Use `secondary` (#71749a) as a "Glow" source. Place a soft radial gradient of this color behind a primary module to suggest it is "illuminated" by the user's attention.

---

## 5. Components: The Spatial Building Blocks

### Buttons (The "Actuators")
- **Primary:** Gradient-filled (Primary to Primary Container), `xl` roundedness (1.5rem). No border.
- **Secondary:** Glassmorphic (`surface_variant` at 40% + blur) with a `secondary` text color.
- **Tertiary:** Pure text using `primary_fixed` (#dee0ff), with a subtle underline that expands on hover.

### Progress "Rooms" (Custom Component)
Instead of a standard progress bar, use a series of **Connected Nodes**. Each node is a `secondary_container` (#1ea296) circle that glows (`secondary` outer glow) when active.

### Cards & Lists
**Strict Rule:** No divider lines. Use `spacing-6` (2rem) of vertical white space to separate list items. Cards should use `surface_container_low` and transition to `surface_container_highest` on hover to "lift" toward the user.

### Input Fields
Inputs should feel like "Sinks" in the interface. Use `surface_container_lowest` for the field background with an `sm` (0.25rem) corner radius. The label (`label-md`) should sit 0.5rem above the field, never inside it.

---

## 6. Do’s and Don’ts

### Do:
- **Do** use `secondary_fixed_dim` (#66d9cc) for success states to keep the "Zen" teal vibe.
- **Do** allow elements to overlap (e.g., an image "breaking" the boundary of a container).
- **Do** use the `24` spacing token (8.5rem) for top-level section margins to provide "Spatial Breath."

### Don’t:
- **Don't** use pure black or pure white. Use `surface` (#10141a) and `on_surface` (#dfe2eb).
- **Don't** use 90-degree corners. Everything must have at least `sm` (0.25rem) roundedness to feel organic.
- **Don't** use standard "Slide-in" animations. Use "Fade and Scale" (from 95% to 100%) to mimic objects appearing from the depth of the room.