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
