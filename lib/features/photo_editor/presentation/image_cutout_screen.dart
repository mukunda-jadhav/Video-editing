import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/media/native_media_service.dart';
import '../../../core/theme/app_theme.dart';
import 'background_refine_screen.dart';

/// Reusable static-image cutout route for video overlays. Photo canvases expose
/// the same automatic and brush actions directly in their Background panel.
class ImageCutoutScreen extends StatefulWidget {
  const ImageCutoutScreen({
    super.key,
    required this.originalPath,
    this.maskPath,
  });
  final String originalPath;
  final String? maskPath;
  @override
  State<ImageCutoutScreen> createState() => _ImageCutoutScreenState();
}

class _ImageCutoutScreenState extends State<ImageCutoutScreen> {
  final _native = const NativeMediaService();
  late String _path = widget.maskPath ?? widget.originalPath;
  bool _busy = false;
  bool _closing = false;
  String? _error;

  Future<void> _automatic() async {
    if (_busy || _closing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await _native.removeBackground(widget.originalPath);
      if (mounted && !_closing) setState(() => _path = path);
    } catch (e) {
      if (mounted && !_closing) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manual() async {
    if (_busy || _closing) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BackgroundRefineScreen(
          originalPath: widget.originalPath,
          initialMaskPath: _path == widget.originalPath ? null : _path,
        ),
      ),
    );
    if (mounted && path != null) {
      setState(() {
        _path = path;
        _error = null;
      });
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    if (_busy) await _native.cancelBackgroundRemoval();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (_busy) unawaited(_native.cancelBackgroundRemoval());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy || _closing,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel cutout',
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
        title: const Text('Image cutout'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(_path),
            child: const Text('Apply'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.file(
                    File(_path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('This image could not be opened.'),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text('Removing background on your device…'),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _automatic,
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Auto remove'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _manual,
                        icon: const Icon(Icons.brush_outlined),
                        label: const Text('Erase / Restore'),
                      ),
                      TextButton(
                        onPressed: _busy || _closing
                            ? null
                            : () => setState(() => _path = widget.originalPath),
                        child: const Text('Restore original'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
