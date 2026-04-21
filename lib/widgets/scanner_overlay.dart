import 'package:flutter/material.dart';

class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({Key? key}) : super(key: key);

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: HolePainter(),
          ),
        ),
        Center(
          child: SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: ScannerCornerPainter(),
                  ),
                ),
                // Scanning Laser Animation
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return Positioned(
                      top: 260 * _animation.value,
                      left: 10,
                      right: 10,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4CAF50).withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF4CAF50).withOpacity(0),
                              const Color(0xFF4CAF50),
                              const Color(0xFF4CAF50).withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class HolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.7);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 260, height: 260),
            const Radius.circular(30),
          ))
          ..close(),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ScannerCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1B5E20)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const length = 40.0;
    const radius = 30.0;

    // Top Left
    canvas.drawPath(
      Path()
        ..moveTo(0, length)
        ..lineTo(0, radius)
        ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
        ..lineTo(length, 0),
      paint,
    );

    // Top Right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, 0)
        ..lineTo(size.width - radius, 0)
        ..arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius))
        ..lineTo(size.width, length),
      paint,
    );

    // Bottom Left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - length)
        ..lineTo(0, size.height - radius)
        ..arcToPoint(Offset(radius, size.height), radius: const Radius.circular(radius), clockwise: false)
        ..lineTo(length, size.height),
      paint,
    );

    // Bottom Right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, size.height)
        ..lineTo(size.width - radius, size.height)
        ..arcToPoint(Offset(size.width, size.height - radius), radius: const Radius.circular(radius), clockwise: false)
        ..lineTo(size.width, size.height - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
