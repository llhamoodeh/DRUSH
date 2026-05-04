import 'package:flutter/material.dart';

/// Full-screen celebration overlay with large emojis flowing in from both sides.
class CelebrationOverlay extends StatefulWidget {
  final Duration duration;
  const CelebrationOverlay({super.key, this.duration = const Duration(milliseconds: 2000)});

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)..forward();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Material(
      color: Colors.transparent,
      child: IgnorePointer(
        ignoring: true,
        child: Stack(
          children: [
            // Left side emoji flow
            ..._buildEmojiStream(size, isLeft: true),
            // Right side emoji flow
            ..._buildEmojiStream(size, isLeft: false),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEmojiStream(Size size, {required bool isLeft}) {
    const emojis = ['🎊', '🎉', '🎊', '🎉', '✨'];
    const emojiCount = 12;
    const fontSize = 80.0;

    return List.generate(emojiCount, (i) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          // stagger each emoji
          final stagger = i * 0.08;
          final adjustedT = (_ctrl.value - stagger).clamp(0.0, 1.0);
          
          // progress through animation
          final progress = Curves.easeInOut.transform(adjustedT);
          
          // horizontal: moves from edge to center
          final startX = isLeft ? -fontSize : size.width;
          final endX = size.width / 2;
          final x = startX + (endX - startX) * progress;
          
          // vertical: sine wave motion for fun
          final yOffset = 80.0 * (1 - (adjustedT - 0.5).abs() * 2).clamp(0.0, 1.0);
          final baseY = (i % 4) * (size.height / 4) + 40;
          final y = baseY + yOffset;
          
          // scale and fade
          final scale = 0.3 + progress * 0.9;
          final opacity = progress < 0.1 ? progress * 10 : (1 - (progress - 0.9) * 10).clamp(0.0, 1.0);
          
          return Positioned(
            left: x,
            top: y,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Text(
                  emojis[i % emojis.length],
                  style: const TextStyle(fontSize: fontSize),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
