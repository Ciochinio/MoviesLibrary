import 'dart:math';
import 'package:flutter/material.dart';

/// Placeholder wheel painter. Draws N equal segments with alternating colours
/// and a label in each. Animation will be layered on top of this later.
class WheelPainter extends CustomPainter {
  final List<String> labels;
  final double rotationAngle; // radians, drives spin animation
  final List<Color> segmentColors;

  WheelPainter({
    required this.labels,
    required this.rotationAngle,
    List<Color>? segmentColors,
  }) : segmentColors = segmentColors ?? _defaultColors;

  static const _defaultColors = [
    Color(0xFF7C3AED),
    Color(0xFF9D5CF6),
    Color(0xFF5B21B6),
    Color(0xFFBB8AF8),
    Color(0xFF4C1D95),
    Color(0xFFDDB6FE),
    Color(0xFF6D28D9),
    Color(0xFFEDE9FE),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final segmentAngle = (2 * pi) / labels.length;

    final paint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1.5;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationAngle);

    for (int i = 0; i < labels.length; i++) {
      final startAngle = segmentAngle * i - pi / 2;

      // Segment fill
      paint.color = segmentColors[i % segmentColors.length];
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        startAngle,
        segmentAngle,
        true,
        paint,
      );

      // Segment border
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        startAngle,
        segmentAngle,
        true,
        borderPaint,
      );

      // Label
      _drawLabel(canvas, labels[i], startAngle, segmentAngle, radius);
    }

    // Centre dot
    canvas.drawCircle(
      Offset.zero,
      12,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset.zero,
      10,
      Paint()..color = const Color(0xFF7C3AED),
    );

    canvas.restore();
  }

  void _drawLabel(
    Canvas canvas,
    String label,
    double startAngle,
    double segmentAngle,
    double radius,
  ) {
    final midAngle = startAngle + segmentAngle / 2;
    final labelRadius = radius * 0.62;
    final x = cos(midAngle) * labelRadius;
    final y = sin(midAngle) * labelRadius;

    // Truncate long labels
    final displayLabel = label.length > 14 ? '${label.substring(0, 12)}…' : label;

    final tp = TextPainter(
      text: TextSpan(
        text: displayLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(blurRadius: 3, color: Colors.black54),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: radius * 0.55);

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(midAngle + pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(WheelPainter oldDelegate) =>
      oldDelegate.rotationAngle != rotationAngle ||
      oldDelegate.labels.length != labels.length;
}

/// The pointer/arrow that sits above the wheel to indicate the winning segment.
class WheelPointerPainter extends CustomPainter {
  final Color color;

  const WheelPointerPainter({this.color = const Color(0xFFFFFFFF)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black38
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Triangle pointing downward
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WheelPointerPainter _) => false;
}
