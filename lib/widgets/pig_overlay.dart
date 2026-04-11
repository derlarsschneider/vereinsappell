import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

const double _pigSize = 100.0;
const Duration _totalDuration = Duration(seconds: 10);
// Pig speed in logical pixels per second
const double _pigSpeed = 280.0;

/// Inserts a pig that runs across the screen for 10 seconds, then removes itself.
void showPigOverlay(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PigOverlay(onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

/// Inserts a dancing animation overlay for fine (Strafe) notifications.
///
/// [animationPath] – Lottie asset to play (default: Piggy Bank - Dancing).
/// [size]          – Width and height of the animation in logical pixels.
/// [duration]      – How long the overlay stays on screen.
void showFineOverlay(
  BuildContext context, {
  String animationPath = 'assets/animations/piggy_bank_dancing.json',
  double size = 150.0,
  Duration duration = const Duration(seconds: 10),
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _DancingOverlay(
      onDone: () => entry.remove(),
      animationPath: animationPath,
      size: size,
      duration: duration,
    ),
  );
  overlay.insert(entry);
}

class _PigOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const _PigOverlay({required this.onDone});

  @override
  State<_PigOverlay> createState() => _PigOverlayState();
}

class _PigOverlayState extends State<_PigOverlay> {
  final _random = Random();

  double _x = -_pigSize;
  double _y = 0;
  bool _facingRight = true;
  Duration _animDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    Timer(_totalDuration, () {
      if (mounted) widget.onDone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _runNext());
  }

  Future<void> _runNext() async {
    if (!mounted) return;

    final size = MediaQuery.of(context).size;
    final newY = _random.nextDouble() * (size.height - _pigSize * 2).clamp(0, double.infinity);

    // Snap to the starting edge (off-screen), no animation
    setState(() {
      _facingRight = !_facingRight;
      _x = _facingRight ? -_pigSize : size.width;
      _y = newY;
      _animDuration = Duration.zero;
    });

    // Let the snap frame render before starting the animated move
    await Future.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;

    final crossMs = ((size.width + _pigSize * 2) / _pigSpeed * 1000).round();
    setState(() {
      _x = _facingRight ? size.width : -_pigSize;
      _animDuration = Duration(milliseconds: crossMs);
    });

    // Wait for the pig to finish crossing, then start next run with a short pause
    await Future.delayed(Duration(milliseconds: crossMs + 100 + _random.nextInt(400)));
    _runNext();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedPositioned(
        duration: _animDuration,
        curve: Curves.linear,
        left: _x,
        top: _y,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scale(_facingRight ? 1.0 : -1.0, 1.0),
          child: SizedBox(
            width: _pigSize,
            height: _pigSize,
            child: Lottie.asset(
              'assets/animations/piggy_bank_dancing.json',
              repeat: true,
              frameRate: FrameRate.max,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dancing overlay (used for Strafen / fine notifications)
// ---------------------------------------------------------------------------

class _DancingOverlay extends StatefulWidget {
  final VoidCallback onDone;
  final String animationPath;
  final double size;
  final Duration duration;

  const _DancingOverlay({
    required this.onDone,
    required this.animationPath,
    required this.size,
    required this.duration,
  });

  @override
  State<_DancingOverlay> createState() => _DancingOverlayState();
}

class _DancingOverlayState extends State<_DancingOverlay> {
  final _random = Random();
  double _opacity = 0.0;
  double _x = 0;
  double _y = 0;

  @override
  void initState() {
    super.initState();
    Timer(widget.duration, () {
      if (mounted) {
        setState(() => _opacity = 0.0);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) widget.onDone();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      setState(() {
        _x = _random.nextDouble() * (size.width - widget.size).clamp(0, double.infinity);
        _y = _random.nextDouble() * (size.height - widget.size * 1.5).clamp(0, double.infinity);
        _opacity = 1.0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Positioned(
        left: _x,
        top: _y,
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 400),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Lottie.asset(
              widget.animationPath,
              repeat: true,
              frameRate: FrameRate.max,
            ),
          ),
        ),
      ),
    );
  }
}
