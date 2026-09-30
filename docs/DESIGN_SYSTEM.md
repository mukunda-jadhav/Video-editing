# FrameLab design system

Original dark, beginner-friendly Android creative studio. Local UI/UX design research informed responsive layout, touch targets and contrast. The broad search's motion-heavy portfolio recommendations were adapted to a lightweight editor: no looping animation, remote fonts, videos, blur-heavy backgrounds or borrowed product assets.

## Tokens

`lib/core/theme/app_theme.dart` is the executable source of truth.

| Role | Color |
|---|---|
| Background | `#101116` |
| Surface | `#1A1C24` |
| Raised surface | `#232630` |
| Primary lavender | `#B4A0FF` |
| Accent lime | `#D4EF89` |
| Main text | `#F5F3FA` |
| Secondary text | `#ACACBD` |
| Decorative separator | `#363845` |

System sans-serif typography and five bundled document font families work on first launch offline. Material icons and original canvas compositions are bundled; no stock media, proprietary UI assets, CDN, or runtime font download. Artwork text is decorative and excluded from semantics; template controls provide readable semantic descriptions.

## Layout and interaction

- 24dp phone gutters, 1048dp bounded home content; 4/8dp spacing rhythm.
- Creation cards flow to a column on narrow screens or large system type.
- Home / Projects / Pro bottom navigation preserves tab scroll state.
- Content scrolls around Android safe areas; no orientation lock.
- Android controls target at least 48dp. All actions have Material feedback.
- Static original template previews have horizontal scroll with a visible Explore alternative.
- No custom perpetual animations; platform Material motion defaults, and tests include reduced-motion settings.
- The app uses the requested dark theme throughout home, library, editors and settings.

## Editor interaction

Photo editing keeps the canvas above a labelled bottom toolbar, with undo/redo and export in the header. Layer selection opens move/size/rotation/order controls, and text entry uses a focused dialog. Video editing uses a selectable clip timeline, trim controls, canvas crop/zoom controls and a rendered-preview player. Reorder buttons provide an alternative to dragging. Tool panels scroll on small screens; large text increases their height instead of clipping labels. Expensive operations expose progress and cancellation or failure feedback.

Preview and export share each editor's recipe. Video playback requires rendering a 480p preview after changes. Guest workflows do not open an account form; only Buy does. Locked tools explain the Premium requirement while leaving free editing accessible.
