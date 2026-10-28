import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand_anim.dart';

const _c0 = Color(0xFF2563EB); // neon blue
const _c1 = Color(0xFF22D3EE); // neon cyan

/// App-wide brand state: a pulse counter (bumped on every navigation) and a
/// flag to hide the corner logo (e.g. while a video plays full screen).
class BrandBus {
  static final pulse = ValueNotifier<int>(0);
  static final hidden = ValueNotifier<bool>(false);
  static void beat() => pulse.value++;
}

/// Makes the logo beat on every push / pop (including the back button).
class BrandNavObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) => BrandBus.beat();
  @override
  void didPop(Route route, Route? previousRoute) => BrandBus.beat();
}

/// Sits above every screen. During the intro the full animated logo plays in the
/// centre over a dark backdrop; then it glides to the top corner — left for
/// Arabic (RTL), right for English (LTR) — and stays alive there.
class BrandOverlay extends StatelessWidget {
  final bool intro;
  final Widget child;
  const BrandOverlay({super.key, required this.intro, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final shortest = mq.size.shortestSide;
    final big = (shortest * 0.7).clamp(220.0, 460.0);
    final wide = mq.size.width >= 900;
    final miniH = wide ? 54.0 : 44.0;
    const dur = Duration(milliseconds: 900);
    const curve = Curves.easeInOutCubic;
    return Stack(children: [
      child,
      IgnorePointer(
        ignoring: !intro,
        child: AnimatedOpacity(
          opacity: intro ? 1 : 0,
          duration: dur,
          curve: curve,
          child: const ColoredBox(color: Color(0xFF0A0A0A), child: SizedBox.expand()),
        ),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: BrandBus.hidden,
        builder: (_, hidden, __) => IgnorePointer(
          child: AnimatedOpacity(
            opacity: hidden && !intro ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: SafeArea(
              child: AnimatedAlign(
                alignment: intro ? Alignment.center : AlignmentDirectional.topEnd.resolve(Directionality.of(context)),
                duration: dur,
                curve: curve,
                child: Padding(
                  padding: EdgeInsets.all(intro ? 0 : (wide ? 14 : 8)),
                  child: AnimatedContainer(
                    duration: dur,
                    curve: curve,
                    width: intro ? big : miniH * 2.4,
                    height: intro ? big : miniH,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      switchInCurve: Curves.easeOut,
                      child: intro
                          ? FittedBox(key: const ValueKey('full'), child: AnimatedBrand(service: 'SAVER', size: big))
                          : MiniBrand(key: const ValueKey('mini'), height: miniH),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Compact corner logo: the line-heart-line over RA7AL, beating every few
/// seconds and on every navigation pulse.
class MiniBrand extends StatefulWidget {
  final double height;
  const MiniBrand({super.key, required this.height});
  @override
  State<MiniBrand> createState() => _MiniBrandState();
}

class _MiniBrandState extends State<MiniBrand> with TickerProviderStateMixin {
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    BrandBus.pulse.addListener(_onPulse);
  }

  void _onPulse() => _pulse.forward(from: 0);

  @override
  void dispose() {
    BrandBus.pulse.removeListener(_onPulse);
    _idle.dispose();
    _pulse.dispose();
    super.dispose();
  }

  static double _beat(double t) {
    if (t <= 0 || t >= 1) return 1;
    final b1 = math.exp(-math.pow((t - 0.2) / 0.08, 2)) * 0.16;
    final b2 = math.exp(-math.pow((t - 0.48) / 0.08, 2)) * 0.10;
    return 1 + b1 + b2;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _pulse]),
      builder: (_, __) {
        final idle = _beat(_idle.value / 0.5); // beats in the first half of each loop
        final nav = _pulse.isAnimating ? _beat(_pulse.value) : 1.0;
        final scale = math.max(idle, nav);
        final glow = (scale - 1) * 5;
        return SizedBox(
          width: h * 2.4,
          height: h,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: h * 2.2,
              height: h * 0.48,
              child: CustomPaint(painter: _MiniHeartPainter(scale: scale, sweep: _pulse.isAnimating ? _pulse.value : 1.0)),
            ),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [_c0, _c1]).createShader(r),
              child: Text(
                'RA7AL',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: h * 0.4,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [Shadow(color: _c1.withValues(alpha: (0.35 + glow).clamp(0.0, 1.0)), blurRadius: h * 0.25)],
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _MiniHeartPainter extends CustomPainter {
  final double scale, sweep;
  _MiniHeartPainter({required this.scale, required this.sweep});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final y = h * 0.86, x0 = w * 0.04, x1 = w * 0.92, cx = (x0 + x1) / 2;
    final sc = (h * 0.8) / 29.0;
    final path = Path()..moveTo(x0, y);
    path.lineTo(cx, y);
    for (var i = 0; i <= 120; i++) {
      final t = math.pi + 2 * math.pi * i / 120;
      final hx = 16 * math.pow(math.sin(t), 3);
      final hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
      final px = cx + hx * sc, py = (y - 15 * sc) - hy * sc;
      path.lineTo(cx + (px - cx) * scale, y + (py - y) * scale);
    }
    path.lineTo(x1, y);
    final shader = const LinearGradient(colors: [_c0, _c1]).createShader(Offset.zero & size);
    final sw = math.max(1.6, h * 0.09);
    canvas.drawPath(
      path,
      Paint()
        ..color = _c1.withValues(alpha: (0.25 + (scale - 1) * 4).clamp(0.0, 0.9))
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * 2.6
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 1.5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // a light "pulse" travelling along the line on navigation
    if (sweep < 1) {
      final m = path.computeMetrics().first;
      final pos = m.getTangentForOffset(m.length * sweep)?.position;
      if (pos != null) canvas.drawCircle(pos, sw * 1.4, Paint()..color = const Color(0xFFE0FBFF));
    }
    canvas.drawCircle(Offset(x1, y), sw * 1.5 * (1 + (scale - 1) * 2), Paint()..color = _c1);
  }

  @override
  bool shouldRepaint(covariant _MiniHeartPainter o) => o.scale != scale || o.sweep != sweep;
}
