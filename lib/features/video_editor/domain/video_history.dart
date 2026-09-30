import 'dart:convert';

import 'video_document.dart';

/// Bounded recipe history, never frame buffers or media copies.
class VideoHistory {
  VideoHistory(VideoDocument initial, {this.limit = 40}) : _past = [initial];
  final int limit;
  final List<VideoDocument> _past;
  final List<VideoDocument> _future = [];
  bool get canUndo => _past.length > 1;
  bool get canRedo => _future.isNotEmpty;
  VideoDocument get current => _past.last;

  void commit(VideoDocument document) {
    if (jsonEncode(document.toJson()) == jsonEncode(current.toJson())) return;
    _past.add(document);
    if (_past.length > limit) _past.removeAt(0);
    _future.clear();
  }

  VideoDocument undo() {
    if (canUndo) _future.add(_past.removeLast());
    return current;
  }

  VideoDocument redo() {
    if (canRedo) _past.add(_future.removeLast());
    return current;
  }
}

/// Split a source range without re-encoding or changing total running time.
List<VideoClip> splitVideoClip(
  VideoClip clip,
  double sourceTime,
  String newId,
) {
  if (!sourceTime.isFinite ||
      sourceTime <= clip.start + .04 ||
      sourceTime >= clip.end - .04) {
    throw ArgumentError('Choose a split point inside the selected clip.');
  }
  return [
    clip.copyWith(end: sourceTime, transition: VideoTransition.cut),
    clip.copyWith(id: newId, start: sourceTime),
  ];
}
