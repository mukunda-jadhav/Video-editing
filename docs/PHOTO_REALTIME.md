# Photo editor live preview

Brightness, exposure, contrast, saturation, all filter looks, blur, crop, rotation,
flip, canvas ratio/size, and layer geometry update on the next Flutter frame.
Changing them reuses the decoded native texture instead of decoding media,
encoding PNGs, or sending pixels to a CPU worker.

Source textures load only when their media paths change. Preview foregrounds
are bounded to 1200 px; overlays share a four-million-pixel decode budget.
Undo stores recipes, not pixel buffers. Slider drags commit one undo/save entry
when released. The PNG exporter uses the same Canvas geometry/color/blur
pipeline with up to 4096 px output and a twelve-million-pixel overlay budget.
All photo filters, fonts, stickers, background removal and export are free.

No paid APIs or media uploads are involved. First import, background removal,
and final PNG encoding still take time; tight crops can look softer in the
bounded preview than in export. Exact frame rate depends on the phone/GPU,
especially with blur or many text/image layers.

Changed files:
- `lib/features/photo_editor/data/photo_renderer.dart`
- `lib/features/photo_editor/domain/photo_document.dart`
- `lib/features/photo_editor/presentation/photo_editor_screen.dart`
- `test/photo_renderer_test.dart`
- `test/photo_document_test.dart`
- `test/photo_editor_test.dart`

No new dependencies. Run:

```powershell
flutter test --no-pub test/photo_editor_test.dart test/photo_renderer_test.dart test/photo_document_test.dart
```

Regression coverage includes frame-by-frame slider/crop/ratio feedback, one
commit per drag, undo, actual blur pixels, texture reuse after deleting the
original fixture file, and per-pixel preview/export equivalence for combined
brightness/exposure/contrast/saturation/filter/crop/rotation/flip.
