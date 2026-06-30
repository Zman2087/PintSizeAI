import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Renders a live stock quote with a sparkline chart inside a chat message.
///
/// The data is embedded in assistant message text between
/// `<pintsize-stock>` … `</pintsize-stock>` as JSON, so it persists like any
/// other message and is detected by [MessageContent].
class StockChartCard extends StatelessWidget {
  const StockChartCard({super.key, required this.json});

  /// The JSON payload (the inner text of the marker).
  final String json;

  static const startMarker = '<pintsize-stock>';
  static const endMarker = '</pintsize-stock>';

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }

    final symbol = data['symbol'] as String? ?? '';
    final name = data['name'] as String? ?? symbol;
    final price = (data['price'] as num?)?.toDouble() ?? 0;
    final change = (data['change'] as num?)?.toDouble() ?? 0;
    final changePct = (data['changePercent'] as num?)?.toDouble() ?? 0;
    final currency = data['currency'] as String? ?? 'USD';
    final closes = ((data['closes'] as List?) ?? const [])
        .map((e) => (e as num).toDouble())
        .toList();
    final up = change >= 0;
    final accent = up ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(symbol,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${price.toStringAsFixed(2)} $currency',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          color: accent, size: 18),
                      Text(
                        '${change.abs().toStringAsFixed(2)} (${changePct.abs().toStringAsFixed(2)}%)',
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (closes.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(closes, accent),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Past month',
                style: TextStyle(color: AppColors.textDim, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

    final dx = size.width / (values.length - 1);
    Offset pointAt(int i) {
      final x = dx * i;
      final y = size.height - ((values[i] - minV) / range) * size.height;
      return Offset(x, y);
    }

    final path = Path()..moveTo(0, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    // Soft fill under the line.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}
