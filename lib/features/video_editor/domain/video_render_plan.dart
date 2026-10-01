import 'dart:math' as math;

import 'video_document.dart';
import 'video_realtime_preview.dart';

/// Pure render compiler. User strings are never interpolated into shell
/// commands. Filter expressions contain only validated numbers and enums;
/// text is loaded from a UTF-8 file with expansion disabled.
class VideoRenderPlan {
  VideoRenderPlan(this.document, {required this.shortEdge}) {
    if (![480, 720, 1080].contains(shortEdge)) {
      throw ArgumentError('Only preview, 720p and 1080p are enabled.');
    }
    if (document.clips.isEmpty) {
      throw ArgumentError('Add a video first.');
    }
    if (document.clips.length > VideoEditingLimits.clips) {
      throw ArgumentError(
        'This project has more than ${VideoEditingLimits.clips} clips. Remove clips or divide it into smaller projects before rendering. Your saved project is unchanged.',
      );
    }
    if (document.overlays.length > VideoEditingLimits.overlays) {
      throw ArgumentError(
        'Use at most ${VideoEditingLimits.overlays} image overlays per project. Your saved project is unchanged.',
      );
    }
    if (document.texts.length > VideoEditingLimits.textLayers) {
      throw ArgumentError(
        'This project has more than ${VideoEditingLimits.textLayers} text layers. Remove some layers before rendering. Your saved project is unchanged.',
      );
    }
    if (!document.aspectRatio.isFinite || document.aspectRatio <= 0) {
      throw ArgumentError('Invalid video dimensions.');
    }
    if (width > 4096 || height > 4096) {
      throw ArgumentError(
        'This canvas is too wide or tall. Choose a social canvas ratio.',
      );
    }
    for (final clip in document.clips) {
      if (!clip.start.isFinite ||
          !clip.end.isFinite ||
          !clip.speed.isFinite ||
          !clip.sourceDuration.isFinite ||
          clip.start < 0 ||
          clip.end <= clip.start ||
          clip.end > clip.sourceDuration ||
          clip.speed < .25 ||
          clip.speed > 4 ||
          clip.width <= 0 ||
          clip.height <= 0 ||
          !clip.volume.isFinite ||
          clip.volume < 0 ||
          clip.volume > 2 ||
          !clip.zoom.isFinite ||
          clip.zoom < .1 ||
          clip.zoom > 4 ||
          !clip.positionX.isFinite ||
          clip.positionX.abs() > 2 ||
          !clip.positionY.isFinite ||
          clip.positionY.abs() > 2 ||
          !clip.filterIntensity.isFinite ||
          clip.filterIntensity < 0 ||
          clip.filterIntensity > 1 ||
          !clip.cropX.isFinite ||
          clip.cropX < 0 ||
          clip.cropX > 1 ||
          !clip.cropY.isFinite ||
          clip.cropY < 0 ||
          clip.cropY > 1 ||
          !clip.brightness.isFinite ||
          clip.brightness < -.5 ||
          clip.brightness > .5 ||
          !clip.contrast.isFinite ||
          clip.contrast < 0 ||
          clip.contrast > 2 ||
          !clip.saturation.isFinite ||
          clip.saturation < 0 ||
          clip.saturation > 2 ||
          !clip.exposure.isFinite ||
          clip.exposure < -2 ||
          clip.exposure > 2) {
        throw ArgumentError('The timeline contains an invalid clip.');
      }
    }
  }
  final VideoDocument document;
  final int shortEdge;
  int _even(double n) => math.max(2, (n / 2).round() * 2);
  int get width => document.aspectRatio >= 1
      ? _even(shortEdge * document.aspectRatio)
      : shortEdge;
  int get height => document.aspectRatio >= 1
      ? shortEdge
      : _even(shortEdge / document.aspectRatio);

  static String number(num value) => value.toStringAsFixed(6);

  static String filterPath(String path) => path
      .replaceAll('\\', '/')
      .replaceAll(':', '\\:')
      .replaceAll("'", "'\\''");

  static const common = [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-nostdin',
    '-filter_complex_threads',
    '1',
    '-filter_threads',
    '1',
  ];
  static const intermediateCodec = [
    '-c:v',
    'mpeg4',
    '-q:v',
    '2',
    '-threads',
    '2',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-b:a',
    '192k',
    '-ar',
    '48000',
    '-ac',
    '2',
  ];

  static String filterFor(VideoFilter filter, [double intensity = 1]) {
    final i = intensity.clamp(0, 1);
    if (i == 0 || filter == VideoFilter.original) return 'null';
    if (i == 1) {
      return switch (filter) {
        VideoFilter.original => 'null',
        VideoFilter.mono => 'hue=s=0',
        VideoFilter.vivid =>
          'hue=s=1.3,lutrgb=r=clip((val-128)*1.08+128\\,0\\,255):g=clip((val-128)*1.08+128\\,0\\,255):b=clip((val-128)*1.08+128\\,0\\,255)',
        VideoFilter.warm => 'colorchannelmixer=rr=1.08:gg=1.01:bb=0.9',
        VideoFilter.cool => 'colorchannelmixer=rr=0.9:gg=1.01:bb=1.1',
        VideoFilter.cinema =>
          'hue=s=0.78,colorchannelmixer=rr=1.02:gb=0.04:bb=1.08,vignette=PI/5',
      };
    }
    return switch (filter) {
      VideoFilter.original => 'null',
      VideoFilter.mono => 'hue=s=${number(1 - i)}',
      VideoFilter.vivid =>
        'hue=s=${number(1 + .3 * i)},lutrgb=r=clip((val-128)*${number(1 + .08 * i)}+128\\,0\\,255):g=clip((val-128)*${number(1 + .08 * i)}+128\\,0\\,255):b=clip((val-128)*${number(1 + .08 * i)}+128\\,0\\,255)',
      VideoFilter.warm =>
        'colorchannelmixer=rr=${number(1 + .08 * i)}:gg=${number(1 + .01 * i)}:bb=${number(1 - .1 * i)}',
      VideoFilter.cool =>
        'colorchannelmixer=rr=${number(1 - .1 * i)}:gg=${number(1 + .01 * i)}:bb=${number(1 + .1 * i)}',
      VideoFilter.cinema =>
        'hue=s=${number(1 - .22 * i)},colorchannelmixer=rr=${number(1 + .02 * i)}:gb=${number(.04 * i)}:bb=${number(1 + .08 * i)},vignette=PI/${number(5 / i)}',
    };
  }

  static String adjustmentFor(VideoClip clip) {
    if (clip.brightness == 0 &&
        clip.contrast == 1 &&
        clip.saturation == 1 &&
        clip.exposure == 0) {
      return 'null';
    }
    final exposure = math.pow(2, clip.exposure).toDouble();
    final gain = number(clip.contrast * exposure);
    final offset = number(
      128 * (1 - clip.contrast) * exposure + clip.brightness * 255,
    );
    final lut = 'clip(val*$gain+$offset\\,0\\,255)';
    return 'hue=s=${number(clip.saturation)},lutrgb=r=$lut:g=$lut:b=$lut';
  }

  static String tempo(double speed) {
    if (speed < .5) {
      return 'atempo=0.5,atempo=${number(speed * 2)}';
    }
    if (speed > 2) {
      return 'atempo=2,atempo=${number(speed / 2)}';
    }
    return 'atempo=${number(speed)}';
  }

  List<String> normalize(VideoClip clip, String output) {
    final duration = number(clip.duration);
    final zoom = number(clip.zoom);
    final ratio = number(document.aspectRatio);
    final crop =
        "crop=w='min(iw\\,ih*$ratio)/$zoom':h='min(ih\\,iw/$ratio)/$zoom':x='(iw-ow)*${number(clip.cropX)}':y='(ih-oh)*${number(clip.cropY)}'";
    final effects = switch (clip.effect) {
      VideoEffect.none => 'null',
      VideoEffect.vignette => 'vignette=PI/4',
      VideoEffect.soft => 'gblur=sigma=1.5',
      VideoEffect.mirror => 'hflip',
      VideoEffect.fade =>
        'fade=t=in:st=0:d=${number(math.min(.4, clip.duration / 3))},fade=t=out:st=${number(math.max(0, clip.duration - .4))}:d=${number(math.min(.4, clip.duration / 3))}',
    };
    // Legacy crops keep their existing output. Translated/fit clips use a
    // bounded visible source crop and a black canvas; no huge zoom texture is
    // allocated in the exporter even at 1080p and 4x zoom.
    final placement = VideoCanvasPlacement.forClip(
      clip,
      canvasWidth: width.toDouble(),
      canvasHeight: height.toDouble(),
    );
    final usePlacement =
        clip.positionX != 0 ||
        clip.positionY != 0 ||
        clip.fit == VideoFit.fit ||
        clip.zoom < 1;
    var videoGraph =
        '[0:v:0]setpts=(PTS-STARTPTS)/${number(clip.speed)},$crop,scale=$width:$height:flags=lanczos,setsar=1,fps=30,settb=AVTB,${filterFor(clip.filter, clip.filterIntensity)},${adjustmentFor(clip)},$effects,format=yuv420p[v]';
    if (usePlacement) {
      final left = math.max(0.0, placement.left);
      final top = math.max(0.0, placement.top);
      final visibleWidth =
          math.min(width.toDouble(), placement.left + placement.width) - left;
      final visibleHeight =
          math.min(height.toDouble(), placement.top + placement.height) - top;
      if (visibleWidth < 2 || visibleHeight < 2) {
        videoGraph =
            'color=c=black:s=$width:$height:r=30:d=$duration,setsar=1,settb=AVTB[v]';
      } else {
        final sourceX = (left - placement.left) / placement.width * clip.width;
        final sourceY = (top - placement.top) / placement.height * clip.height;
        final sourceW = visibleWidth / placement.width * clip.width;
        final sourceH = visibleHeight / placement.height * clip.height;
        final mirrored = clip.effect == VideoEffect.mirror ? 'hflip,' : '';
        final canvasEffects = clip.effect == VideoEffect.mirror
            ? 'null'
            : effects;
        videoGraph =
            '[0:v:0]setpts=(PTS-STARTPTS)/${number(clip.speed)},${mirrored}crop=w=${number(sourceW)}:h=${number(sourceH)}:x=${number(sourceX)}:y=${number(sourceY)},scale=${_even(visibleWidth)}:${_even(visibleHeight)}:flags=lanczos,setsar=1,fps=30,settb=AVTB,${filterFor(clip.filter, clip.filterIntensity)},${adjustmentFor(clip)},pad=w=$width:h=$height:x=${number(left)}:y=${number(top)}:color=black,$canvasEffects,format=yuv420p[v]';
      }
    }
    final graph =
        '$videoGraph;'
        '${clip.hasAudio ? '[0:a:0]asetpts=PTS-STARTPTS,${tempo(clip.speed)},volume=${number(clip.volume)},aresample=48000,aformat=channel_layouts=stereo,apad' : 'anullsrc=r=48000:cl=stereo'},atrim=duration=$duration,asetpts=PTS-STARTPTS[a]';
    return [
      ...common,
      '-ss',
      number(clip.start),
      '-t',
      number(clip.end - clip.start),
      '-i',
      clip.path,
      '-filter_complex',
      graph,
      '-map',
      '[v]',
      '-map',
      '[a]',
      '-t',
      duration,
      ...intermediateCodec,
      '-movflags',
      '+faststart',
      output,
    ];
  }

  List<String> stitch({
    required String left,
    required String right,
    required String output,
    required double leftDuration,
    required int boundary,
  }) {
    final transition = document.clips[boundary].transition;
    final overlap = document.transitionAt(boundary);
    final name = switch (transition) {
      VideoTransition.cut => '',
      VideoTransition.dissolve => 'fade',
      VideoTransition.wipe => 'wipeleft',
      VideoTransition.slide => 'slideleft',
      VideoTransition.circle => 'circleopen',
    };
    final graph = overlap == 0
        ? '[0:v]setpts=PTS-STARTPTS[v0];[1:v]setpts=PTS-STARTPTS[v1];[0:a]asetpts=PTS-STARTPTS[a0];[1:a]asetpts=PTS-STARTPTS[a1];[v0][a0][v1][a1]concat=n=2:v=1:a=1[v][a]'
        : '[0:v]fps=30,settb=AVTB,setpts=PTS-STARTPTS,format=yuv444p[v0];[1:v]fps=30,settb=AVTB,setpts=PTS-STARTPTS,format=yuv444p[v1];[v0][v1]xfade=transition=$name:duration=${number(overlap)}:offset=${number(leftDuration - overlap)},format=yuv420p[v];[0:a][1:a]acrossfade=d=${number(overlap)}:c1=tri:c2=tri[a]';
    return [
      ...common,
      '-i',
      left,
      '-i',
      right,
      '-filter_complex',
      graph,
      '-map',
      '[v]',
      '-map',
      '[a]',
      ...intermediateCodec,
      '-movflags',
      '+faststart',
      output,
    ];
  }

  List<String> finish({
    required String input,
    required String output,
    required Map<String, String> textFiles,
    required Map<String, String> fontFiles,
    String encoder = 'h264_mediacodec',
    String? preparedMusic,
    Map<String, (int, int)> overlaySizes = const {},
  }) {
    if (!['h264_mediacodec', 'mpeg4'].contains(encoder)) {
      throw ArgumentError('Unsupported encoder.');
    }
    if (document.musicPath != null && preparedMusic == null) {
      throw ArgumentError('Prepare a bounded music track before composition.');
    }
    final args = [...common, '-i', input];
    final graph = <String>[];
    var video = '[0:v]';
    var nextInput = 1;
    for (var i = 0; i < document.overlays.length; i++) {
      final overlay = document.overlays[i];
      final sourceSize = overlaySizes[overlay.path];
      var resize = 'scale=${_even(width * overlay.width)}:-2,format=rgba';
      var placementX = overlay.centered
          ? 'W*${number(overlay.x)}-w/2'
          : '(W-w)*${number(overlay.x)}';
      var placementY = overlay.centered
          ? 'H*${number(overlay.y)}-h/2'
          : '(H-h)*${number(overlay.y)}';
      if (sourceSize != null) {
        final imageWidth = _even(width * overlay.width).toDouble();
        final imageHeight = imageWidth * sourceSize.$2 / sourceSize.$1;
        final left = overlay.centered
            ? width * overlay.x - imageWidth / 2
            : (width - imageWidth) * overlay.x;
        final top = overlay.centered
            ? height * overlay.y - imageHeight / 2
            : (height - imageHeight) * overlay.y;
        final visibleLeft = math.max(0.0, left);
        final visibleTop = math.max(0.0, top);
        final visibleWidth =
            math.min(width.toDouble(), left + imageWidth) - visibleLeft;
        final visibleHeight =
            math.min(height.toDouble(), top + imageHeight) - visibleTop;
        // A layer outside the canvas is retained in the recipe, but consumes
        // no image decoder in export. Partial layers crop before scaling.
        if (visibleWidth < 2 || visibleHeight < 2) continue;
        final scale = imageWidth / sourceSize.$1;
        resize =
            'format=rgba,crop=w=${number(visibleWidth / scale)}:h=${number(visibleHeight / scale)}:x=${number((visibleLeft - left) / scale)}:y=${number((visibleTop - top) / scale)},scale=${_even(visibleWidth)}:${_even(visibleHeight)}';
        placementX = number(visibleLeft);
        placementY = number(visibleTop);
      }
      args.addAll([
        '-loop',
        '1',
        '-framerate',
        '30',
        '-t',
        number(document.duration),
        '-i',
        overlay.path,
      ]);
      graph.add(
        '[$nextInput:v]trim=duration=${number(document.duration)},setpts=PTS-STARTPTS,$resize,colorchannelmixer=aa=${number(overlay.opacity)}[ov$i]',
      );
      graph.add(
        '$video[ov$i]overlay=x=$placementX:y=$placementY:enable=\'between(t,${number(overlay.start)},${number(overlay.end)})\':shortest=1[vov$i]',
      );
      video = '[vov$i]';
      nextInput++;
    }
    for (var i = 0; i < document.texts.length; i++) {
      final text = document.texts[i];
      final file = textFiles[text.id];
      final font = fontFiles[text.font];
      if (file == null || font == null) {
        throw ArgumentError(
          'Text and font assets must be prepared before rendering.',
        );
      }
      final color = (text.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
      graph.add(
        '${video}drawtext=fontfile=\'${filterPath(font)}\':textfile=\'${filterPath(file)}\':expansion=none:fontcolor=0x$color:fontsize=${math.max(12, (height * text.size).round())}:x=${text.centered ? 'w*${number(text.x)}-text_w/2' : '(w-text_w)*${number(text.x)}'}:y=${text.centered ? 'h*${number(text.y)}-text_h/2' : '(h-text_h)*${number(text.y)}'}:fix_bounds=${text.centered ? 0 : 1}:box=${text.background ? 1 : 0}:boxcolor=black@0.55:boxborderw=10:enable=\'between(t,${number(text.start)},${number(text.end)})\'[vt$i]',
      );
      video = '[vt$i]';
    }
    graph.add('${video}format=yuv420p[vout]');
    var audio = '0:a';
    if (document.musicPath != null) {
      args.addAll(['-i', preparedMusic!]);
      graph.add(
        '[$nextInput:a:0]asetpts=PTS-STARTPTS,volume=${number(document.musicVolume)}[music]',
      );
      graph.add(
        '[0:a][music]amix=inputs=2:duration=first:dropout_transition=0:normalize=0,alimiter=limit=0.95[aout]',
      );
      audio = '[aout]';
    }
    args.addAll([
      '-filter_complex',
      graph.join(';'),
      '-map',
      '[vout]',
      '-map',
      audio,
      '-c:v',
      encoder,
    ]);
    if (encoder == 'mpeg4') {
      args.addAll(['-q:v', shortEdge >= 1080 ? '2' : '3']);
    } else {
      args.addAll([
        '-b:v',
        shortEdge >= 1080
            ? '10000k'
            : shortEdge == 720
            ? '6000k'
            : '1800k',
      ]);
    }
    args.addAll([
      '-threads',
      '2',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-ar',
      '48000',
      '-ac',
      '2',
      '-pix_fmt',
      'yuv420p',
      '-t',
      number(document.duration),
      '-shortest',
      '-movflags',
      '+faststart',
      output,
    ]);
    return args;
  }

  /// Materialize looping music independently, so the final video graph has
  /// finite inputs and does not retain a looping audio demuxer at shutdown.
  List<String> prepareMusic({
    required String output,
    required int repeats,
    required double offset,
  }) {
    if (document.musicPath == null ||
        repeats < 0 ||
        !offset.isFinite ||
        offset < 0) {
      throw ArgumentError('Choose a valid music track and playback offset.');
    }
    return [
      ...common,
      '-stream_loop',
      '$repeats',
      '-ss',
      number(offset),
      '-i',
      document.musicPath!,
      '-vn',
      '-af',
      'aresample=48000,aformat=channel_layouts=stereo',
      '-t',
      number(document.duration),
      '-c:a',
      'pcm_f32le',
      '-ar',
      '48000',
      '-ac',
      '2',
      '-rf64',
      'auto',
      output,
    ];
  }
}
