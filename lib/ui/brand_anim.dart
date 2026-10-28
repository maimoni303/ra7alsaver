import 'dart:math' as math;

import 'package:flutter/material.dart';

const _c0 = Color(0xFF2563EB); // neon blue
const _c1 = Color(0xFF22D3EE); // neon cyan
const _sub = Color(0xFFBAE6FD);

/// Animated RA7AL AL3OMR logo: the line draws itself into a heart, the dot pops,
/// RA7AL glows in, AL3OMR types out, the service badge pops, then the heart beats.
class AnimatedBrand extends StatefulWidget {
  final String service;
  final double size;
  const AnimatedBrand({super.key, this.service = 'TV', this.size = 320});
  @override
  State<AnimatedBrand> createState() => _AnimatedBrandState();
}

class _AnimatedBrandState extends State<AnimatedBrand> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4000))..repeat();
  bool _firstLoop = true;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (_firstLoop && _c.value > 0.98) _firstLoop = false;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _ease(double t) {
    t = t.clamp(0.0, 1.0);
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  static double _pop(double t) {
    t = t.clamp(0.0, 1.0);
    if (t < 0.6) return _ease(t / 0.6) * 1.15;
    return 1.15 - 0.15 * _ease((t - 0.6) / 0.4);
  }

  static double _beat(double t) {
    if (t <= 0 || t >= 1) return 1;
    final b1 = math.exp(-math.pow((t - 0.18) / 0.07, 2)) * 0.14;
    final b2 = math.exp(-math.pow((t - 0.42) / 0.07, 2)) * 0.09;
    return 1 + b1 + b2;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // After the first loop the intro stays complete and only the heartbeat repeats.
        final t = _firstLoop ? _c.value * 4.0 : 2.0 + _c.value * 2.0;
        final beat = _beat((t - 2.0) / 2.0);
        final textA = _ease((t - 0.6) / 0.8);
        final letters = ((t - 1.2) / 0.5 * 6).clamp(0.0, 6.0);
        final badge = _pop((t - 1.7) / 0.4);
        return SizedBox(
          width: s,
          height: s,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _HeartLinePainter(
                  progress: _ease(t / 1.1),
                  scale: beat,
                  dot: _pop((t - 1.0) / 0.4) * (1 + (beat - 1) * 2),
                  underline: _ease((t - 1.4) / 0.5),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: s * (0.42 + 0.03 * (1 - textA)),
              child: Opacity(
                opacity: textA,
                child: Center(
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(colors: [_c0, _c1]).createShader(r),
                    child: Text(
                      'RA7AL',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: s * 0.2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1,
                        letterSpacing: -s * 0.004,
                        shadows: [Shadow(color: _c1.withValues(alpha: 0.55 * (1 + (beat - 1) * 4)), blurRadius: s * 0.06)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: s * 0.655,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                textDirection: TextDirection.ltr,
                children: [
                  for (var i = 0; i < 6; i++)
                    Opacity(
                      opacity: (letters - i).clamp(0.0, 1.0),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: s * 0.014),
                        child: Text('AL3OMR'[i],
                            style: TextStyle(fontSize: s * 0.07, fontWeight: FontWeight.w300, color: _sub, height: 1)),
                      ),
                    ),
                ],
              ),
            ),
            if (badge > 0)
              Positioned(
                left: 0,
                right: 0,
                top: s * 0.815,
                child: Center(
                  child: Transform.scale(
                    scale: badge,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: s * 0.05, vertical: s * 0.012),
                      decoration: BoxDecoration(color: _c1, borderRadius: BorderRadius.circular(s)),
                      child: Text(widget.service,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              fontSize: s * 0.065, fontWeight: FontWeight.w900, color: const Color(0xFF04212E), height: 1.1)),
                    ),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _HeartLinePainter extends CustomPainter {
  final double progress, scale, dot, underline;
  _HeartLinePainter({required this.progress, required this.scale, required this.dot, required this.underline});

  List<Offset> _points(Size size) {
    final s = size.width;
    final x0 = s * 0.18, x1 = s * 0.82, y = s * 0.30, h = s * 0.17;
    final sc = h / 29.0, cx = (x0 + x1) / 2;
    final pts = <Offset>[];
    for (var i = 0; i < 120; i++) {
      pts.add(Offset(x0 + (cx - x0) * i / 120, y));
    }
    for (var i = 0; i < 360; i++) {
      final t = math.pi + 2 * math.pi * i / 360;
      final hx = 16 * math.pow(math.sin(t), 3);
      final hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
      final px = cx + hx * sc, py = (y - 15 * sc) - hy * sc;
      pts.add(Offset(cx + (px - cx) * scale, y + (py - y) * scale)); // scale around the tip
    }
    for (var i = 0; i <= 120; i++) {
      pts.add(Offset(cx + (x1 - cx) * i / 120, y));
    }
    return pts;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pts = _points(size);
    final n = (pts.length * progress).floor().clamp(0, pts.length);
    if (n > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      final shader = const LinearGradient(colors: [_c0, _c1]).createShader(Rect.fromLTWH(s * 0.18, 0, s * 0.64, s));
      final glow = 0.45 * (1 + (scale - 1) * 5);
      canvas.drawPath(
        path,
        Paint()
          ..color = _c1.withValues(alpha: glow.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.022
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (n < pts.length) {
        canvas.drawCircle(pts[n - 1], s * 0.022, Paint()..color = const Color(0xFFDCFAFF));
      }
    }
    if (dot > 0) {
      canvas.drawCircle(pts.last, s * 0.026 * dot, Paint()..color = _c1);
    }
    if (underline > 0) {
      final w = s * 0.5 * underline;
      final r = Rect.fromLTWH(s * 0.25, s * 0.745, w, s * 0.007);
      canvas.drawRect(r, Paint()..shader = const LinearGradient(colors: [_c0, _c1]).createShader(Rect.fromLTWH(s * 0.25, 0, s * 0.5, s)));
    }
  }

  @override
  bool shouldRepaint(covariant _HeartLinePainter o) =>
      o.progress != progress || o.scale != scale || o.dot != dot || o.underline != underline;
}
