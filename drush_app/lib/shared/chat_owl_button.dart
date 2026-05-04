import 'package:flutter/material.dart';

class ChatOwlButton extends StatelessWidget {
  final double bottom;
  final double left;
  final GlobalKey<NavigatorState> navigatorKey;

  const ChatOwlButton({
    super.key,
    required this.navigatorKey,
    this.bottom = 20,
    this.left = 20,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: left, bottom: bottom),
        child: Material(
          color: Colors.transparent,
          elevation: 10,
          shape: const CircleBorder(),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              navigatorKey.currentState?.pushNamed('/chat');
            },
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(
                    'assets/owl.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
