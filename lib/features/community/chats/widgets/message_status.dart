import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageReceiptState;

class ChatMessageStatusGlyph extends StatefulWidget {
  final ChatMessageReceiptState state;

  const ChatMessageStatusGlyph({super.key, required this.state});

  @override
  State<ChatMessageStatusGlyph> createState() => _ChatMessageStatusGlyphState();
}

class _ChatMessageStatusGlyphState extends State<ChatMessageStatusGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulseController;

  bool get isSending => widget.state == ChatMessageReceiptState.sending;

  @override
  void initState() {
    super.initState();
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    if (isSending) {
      pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ChatMessageStatusGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isSending && !pulseController.isAnimating) {
      pulseController.repeat(reverse: true);
    } else if (!isSending && pulseController.isAnimating) {
      pulseController.stop();
      pulseController.value = 1;
    }
  }

  @override
  void dispose() {
    pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == ChatMessageReceiptState.failed) {
      return const Icon(
        Icons.error_outline_rounded,
        color: Colors.white,
        size: 13,
      );
    }

    final color = widget.state == ChatMessageReceiptState.read
        ? const Color(0xFF00E0C7)
        : Colors.white.withValues(alpha: 0.68);
    final marks = widget.state == ChatMessageReceiptState.read ? 2 : 1;
    final glyph = SizedBox(
      key: ValueKey('${widget.state.name}-$marks'),
      width: 20,
      height: 12,
      child: CustomPaint(
        painter: _ChatMessageStatusPainter(color: color, marks: marks),
      ),
    );

    if (isSending) {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.38, end: 0.92).animate(
          CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
        ),
        child: glyph,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: glyph,
    );
  }
}

class _ChatMessageStatusPainter extends CustomPainter {
  final Color color;
  final int marks;

  const _ChatMessageStatusPainter({required this.color, required this.marks});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.85
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawMark(double left) {
      final path = ui.Path()
        ..moveTo(left, size.height * 0.58)
        ..lineTo(left + 2.8, size.height * 0.82)
        ..lineTo(left + 7.8, size.height * 0.24);
      canvas.drawPath(path, paint);
    }

    if (marks <= 1) {
      drawMark((size.width - 7.8) / 2);
      return;
    }

    drawMark(1.2);
    drawMark(10.8);
  }

  @override
  bool shouldRepaint(covariant _ChatMessageStatusPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.marks != marks;
  }
}

const int chatMessagePageSize = 10;
