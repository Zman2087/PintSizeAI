import 'dart:convert';
import 'package:flutter/material.dart';
import '../features/web_search/stock_service.dart';
import '../theme/theme.dart';

/// Renders a live stock quote with a sparkline chart inside a chat message.
///
/// The data is embedded in assistant message text between
/// `<pintsize-stock>` … `</pintsize-stock>` as JSON, so it persists like any
/// other message and is detected by [MessageContent].
class StockChartCard extends StatefulWidget {
  const StockChartCard({super.key, required this.json});

  /// The JSON payload (the inner text of the marker).
  final String json;

  static const startMarker = '<pintsize-stock>';
  static const endMarker = '</pintsize-stock>';

  @override
  State<StockChartCard> createState() => _StockChartCardState();
}

class _StockChartCardState extends State<StockChartCard> {
  final _service = StockService();
  // Cache of closes per range label; seeded with the embedded 1M data.
  final Map<String, List<double>> _cache = {};
  String _range = '1M';
  bool _loading = false;

  Future<void> _selectRange(String symbol, String label) async {
    if (label == _range && _cache.containsKey(label)) return;
    setState(() => _range = label);
    if (_cache.containsKey(label)) return;
    setState(() => _loading = true);
    final closes = await _service.fetchCloses(symbol, label);
    if (!mounted) return;
    setState(() {
      if (closes.isNotEmpty) _cache[label] = closes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(widget.json) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }

    final symbol = data['symbol'] as String? ?? '';
    final name = data['name'] as String? ?? symbol;
    final price = (data['price'] as num?)?.toDouble() ?? 0;
    final change = (data['change'] as num?)?.toDouble() ?? 0;
    final changePct = (data['changePercent'] as num?)?.toDouble() ?? 0;
    final currency = data['currency'] as String? ?? 'USD';
    _cache.putIfAbsent(
        '1M',
        () => ((data['closes'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList());
    final closes = _cache[_range] ?? const <double>[];
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
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${price.toStringAsFixed(2)} $currency',
                      style: TextStyle(
                          color: AppColors.textPrimary,
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
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            width: double.infinity,
            child: _loading
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : closes.length > 1
                    ? CustomPaint(painter: _SparklinePainter(closes, accent))
                    : Center(
                        child: Text('No chart data for this range',
                            style: TextStyle(
                                color: AppColors.textDim, fontSize: 11))),
          ),
          const SizedBox(height: 8),
          // Time-range selector.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in StockService.chartRanges.keys)
                GestureDetector(
                  onTap: () => _selectRange(symbol, label),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _range == label
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _range == label
                            ? accent
                            : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
