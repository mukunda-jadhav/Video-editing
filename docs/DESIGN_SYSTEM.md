# FrameLab 1.1 editor design

Near-black surfaces, cyan actions, white content and subdued separators. The interface prioritizes a visible canvas, direct manipulation and short labelled tools. Flutter Material controls preserve touch feedback, accessible labels and reduced-motion settings. Original vector template artwork and bundled fonts keep the app offline.

| Role | Color |
|---|---|
| Background | #0D0D10 |
| Surface | #18181C |
| Raised | #242429 |
| Action / selection | #40E0D0 |
| Text | #F6F6F8 |
| Secondary | #A6A6AE |

Home opens with New project, photo/video/template shortcuts and local projects. Navigation is Home / Projects / Templates. There are no purchase, account or advertising screens.

Photo source textures are cached and edited by a live Canvas painter. Video uses the original file in the native video player with live color/crop/layout overlays and a seekable sequence timeline. Expensive composition work is explicit, and export uses the saved recipe. Complex transitions and music mixing still use the exact composed-preview/export path.

Controls use at least 48dp touch targets. Tool panels scroll independently of the preview, and large system text is tested. No remote assets or proprietary product assets are used.


## Editor interaction (1.2)

Tap selects a canvas object; drag moves it; pinch scales. Photo objects can rotate and resize from a corner. Cyan outlines and center guides show selection/alignment. Bottom tools use icon plus label, active state, compact contextual controls and a Done/close action. Nudge/center/fit/fill actions provide alternatives to dragging. Filter cards show the current source and selected look, followed by a strength slider. No proprietary editor assets or catalog are copied.

Background brush mode separates painting from zoom/pan to prevent gesture conflicts. Erase/Restore are explicit labeled tools with brush-size and undo/redo controls. Long processing uses progress and cancel, while source transforms and adjustments update immediately. Flutter [gesture callbacks](https://api.flutter.dev/flutter/widgets/GestureDetector/onScaleUpdate.html) and [canvas compositing](https://api.flutter.dev/flutter/dart-ui/Canvas/saveLayer.html) provide the local interaction/rendering primitives.
