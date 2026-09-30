import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Original vector illustrations. These are preview art, never user projects.
enum TemplateArtStyle { studio, weekend, product }

class TemplateArt extends StatelessWidget {
  const TemplateArt({super.key, required this.style});

  final TemplateArtStyle style;

  @override
  Widget build(BuildContext context) {
    // The surrounding template tile provides the accessible name. Its artwork
    // behaves like an image rather than scaling fragments of decorative text.
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TemplatePainter(style),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TemplatePainter extends CustomPainter {
  const _TemplatePainter(this.style);

  final TemplateArtStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 240);
    switch (style) {
      case TemplateArtStyle.studio:
        _studio(canvas);
      case TemplateArtStyle.weekend:
        _weekend(canvas);
      case TemplateArtStyle.product:
        _product(canvas);
    }
    canvas.restore();
  }

  void _studio(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 240, 240),
      Paint()..color = AppColors.primary,
    );
    canvas.drawCircle(
      const Offset(228, 205),
      100,
      Paint()..color = AppColors.onPrimary,
    );
    canvas.drawCircle(
      const Offset(228, 205),
      70,
      Paint()..color = AppColors.primary,
    );
    canvas.drawCircle(
      const Offset(228, 205),
      40,
      Paint()..color = AppColors.onPrimary,
    );
    _text(
      canvas,
      'THE EVERYDAY',
      const Offset(19, 18),
      10,
      AppColors.onPrimary,
      weight: FontWeight.w600,
      spacing: 2,
    );
    _text(
      canvas,
      'MAKE\nIT YOURS.',
      const Offset(17, 66),
      36,
      AppColors.onPrimary,
      weight: FontWeight.w900,
      height: .98,
    );
    _text(
      canvas,
      'A FRESH PERSPECTIVE',
      const Offset(20, 208),
      9,
      AppColors.onPrimary,
      spacing: 1.2,
    );
    _star(canvas, const Offset(200, 37), 18, AppColors.onPrimary);
  }

  void _weekend(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 240, 240),
      Paint()..color = AppColors.sky,
    );
    canvas.drawCircle(
      const Offset(176, 57),
      32,
      Paint()..color = AppColors.coral,
    );
    final back = Path()
      ..moveTo(0, 143)
      ..quadraticBezierTo(80, 72, 147, 149)
      ..quadraticBezierTo(199, 187, 240, 120)
      ..lineTo(240, 240)
      ..lineTo(0, 240)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF50726B));
    final front = Path()
      ..moveTo(0, 166)
      ..quadraticBezierTo(64, 212, 131, 177)
      ..quadraticBezierTo(195, 144, 240, 185)
      ..lineTo(240, 240)
      ..lineTo(0, 240)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF263E35));
    _text(
      canvas,
      'OFFLINE IS A',
      const Offset(20, 23),
      10,
      const Color(0xFF203B38),
      spacing: 2,
    );
    _text(
      canvas,
      'good\nplace.',
      const Offset(19, 56),
      43,
      const Color(0xFF203B38),
      weight: FontWeight.w800,
      height: .95,
    );
    _text(
      canvas,
      'WEEKEND JOURNAL / 01',
      const Offset(20, 211),
      9,
      AppColors.text,
      spacing: 1.1,
    );
    canvas.drawLine(
      const Offset(204, 211),
      const Offset(220, 211),
      Paint()
        ..color = AppColors.text
        ..strokeWidth = 1.4,
    );
  }

  void _product(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 240, 240),
      Paint()..color = AppColors.accent,
    );
    canvas.drawCircle(
      const Offset(214, 51),
      79,
      Paint()..color = const Color(0xFFBCD874),
    );
    _text(
      canvas,
      'LESS, BUT BETTER.',
      const Offset(18, 18),
      10,
      AppColors.onAccent,
      spacing: 1.4,
    );
    _text(
      canvas,
      'Daily\nessentials.',
      const Offset(18, 51),
      29,
      AppColors.onAccent,
      weight: FontWeight.w800,
      height: 1,
    );
    canvas.save();
    canvas.translate(163, 159);
    canvas.rotate(.2);
    canvas.drawOval(
      const Rect.fromLTWH(-49, 43, 100, 14),
      Paint()..color = const Color(0x22627523),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-24, -45, 50, 91),
        const Radius.circular(13),
      ),
      Paint()..color = const Color(0xFFF1EBD9),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-19, -63, 40, 23),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF2D4537),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-24, -4, 50, 33),
      Paint()..color = const Color(0xFFD5C8AE),
    );
    _text(
      canvas,
      'FORM',
      const Offset(-16, 5),
      11,
      AppColors.onAccent,
      weight: FontWeight.w700,
    );
    canvas.restore();
    _text(
      canvas,
      'MADE FOR YOUR EVERYDAY',
      const Offset(18, 217),
      8,
      AppColors.onAccent,
      spacing: 1,
    );
  }

  void _star(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 16; i++) {
      final angle = i * math.pi / 8;
      final distance = i.isEven ? radius : radius * .34;
      final point =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  void _text(
    Canvas canvas,
    String label,
    Offset offset,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double height = 1.2,
    double? spacing,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: spacing,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 220);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_TemplatePainter oldDelegate) =>
      oldDelegate.style != style;
}
