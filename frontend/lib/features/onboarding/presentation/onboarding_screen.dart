import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
        child: Column(
          children: [
            const Expanded(flex: 4, child: _MarketArtwork()),
            Text(
              'Practice Trading. Build Confidence.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Text(
              'The most realistic paper trading experience to sharpen your skills and build your confidence.',
              maxLines: 3,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => context.push('/auth?mode=signup'),
                child: const Text('Get Started'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/auth?mode=login'),
              child: const Text('Log In'),
            ),
            Text(
              'Virtual money. Real market experience.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MarketArtwork extends StatelessWidget {
  const _MarketArtwork();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _MarketArtworkPainter(
        primary: Theme.of(context).colorScheme.primary,
        cyan: const Color(0xFF28C7E8),
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _MarketArtworkPainter extends CustomPainter {
  _MarketArtworkPainter({required this.primary, required this.cyan});
  final Color primary;
  final Color cyan;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.white.withValues(alpha: .045)..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    for (var y = 0.0; y < size.height; y += 32) canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);

    final points = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final x = size.width * (.06 + i * .1);
      final y = size.height * (.78 - [0.0, .12, .27, .2, .42, .36, .55, .45, .67, .82][i]);
      points.add(Offset(x, y));
      final high = y - 20 - (i % 3) * 6;
      final low = y + 18 + ((i + 1) % 3) * 7;
      final open = y + (i.isEven ? 10 : -8);
      final close = y + (i.isEven ? -12 : 11);
      final paint = Paint()..color = i.isEven ? cyan.withValues(alpha: .75) : primary.withValues(alpha: .72);
      canvas.drawLine(Offset(x, high), Offset(x, low), paint..strokeWidth = 1.5);
      canvas.drawRect(Rect.fromCenter(center: Offset(x, (open + close) / 2), width: 8, height: math.max(8, (open - close).abs())), paint);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) path.lineTo(point.dx, point.dy);
    canvas.drawPath(path, Paint()..color = primary..style = PaintingStyle.stroke..strokeWidth = 2.4);
    for (final point in [points[2], points[6], points.last]) {
      canvas.drawCircle(point, 7, Paint()..color = primary.withValues(alpha: .22));
      canvas.drawCircle(point, 3, Paint()..color = primary);
    }
  }

  @override
  bool shouldRepaint(covariant _MarketArtworkPainter oldDelegate) => oldDelegate.primary != primary || oldDelegate.cyan != cyan;
}
