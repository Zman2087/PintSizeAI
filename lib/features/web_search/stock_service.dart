import 'package:dio/dio.dart';

/// A live stock quote plus recent close prices for a sparkline/chart.
class StockQuote {
  const StockQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.currency,
    required this.closes,
    required this.previousClose,
  });

  final String symbol;
  final String name;
  final double price;
  final double change;
  final double changePercent;
  final String currency;
  final List<double> closes; // recent daily closes for the chart
  final double previousClose;

  bool get isUp => change >= 0;

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        'price': price,
        'change': change,
        'changePercent': changePercent,
        'currency': currency,
        'closes': closes,
      };

  String get summary =>
      '$name ($symbol) is trading at ${price.toStringAsFixed(2)} $currency, '
      '${isUp ? 'up' : 'down'} ${change.abs().toStringAsFixed(2)} '
      '(${changePercent.abs().toStringAsFixed(2)}%) over the last close.';
}

/// Fetches live stock data from Yahoo Finance's public endpoints (no API key).
class StockService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
    },
  ));

  /// Heuristic: does this message look like a stock-price question?
  static bool looksLikeStockQuery(String text) {
    final lower = text.toLowerCase();
    const triggers = [
      'stock', 'share price', 'shares', 'ticker', 'nasdaq', 'nyse',
      'market cap', 'how much is', 'price of', '\$', 'trading at',
      'stock price', 'price for', 'worth right now', 'share value',
      'quote for', 'market price',
    ];
    return triggers.any(lower.contains);
  }

  /// Resolves a company name or ticker to a Yahoo symbol.
  Future<String?> resolveSymbol(String query) async {
    // Bare ticker like $AAPL or AAPL
    final tickerMatch = RegExp(r'\$?([A-Za-z]{1,5})\b').firstMatch(query.trim());
    try {
      final resp = await _dio.get(
        'https://query1.finance.yahoo.com/v1/finance/search',
        queryParameters: {'q': query, 'quotesCount': 1, 'newsCount': 0},
      );
      final quotes = (resp.data['quotes'] as List?) ?? [];
      for (final q in quotes) {
        final sym = (q as Map)['symbol'] as String?;
        if (sym != null && sym.isNotEmpty) return sym;
      }
    } catch (_) {}
    // Fall back to an upper-cased bare ticker if search failed.
    if (tickerMatch != null) return tickerMatch.group(1)!.toUpperCase();
    return null;
  }

  /// Fetches a quote + ~1 month of daily closes for [symbol].
  Future<StockQuote?> fetchQuote(String symbol) async {
    try {
      final resp = await _dio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol',
        queryParameters: {'range': '1mo', 'interval': '1d'},
      );
      final result = (resp.data['chart']?['result'] as List?)?.firstOrNull;
      if (result == null) return null;
      final meta = result['meta'] as Map<String, dynamic>;
      final indicators = result['indicators']?['quote']?[0] as Map?;
      final rawCloses = (indicators?['close'] as List?) ?? const [];
      final closes = rawCloses
          .where((e) => e != null)
          .map((e) => (e as num).toDouble())
          .toList();

      final price = (meta['regularMarketPrice'] as num?)?.toDouble() ??
          (closes.isNotEmpty ? closes.last : 0.0);
      final prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ??
          (meta['previousClose'] as num?)?.toDouble() ??
          (closes.isNotEmpty ? closes.first : price);
      final change = price - prevClose;
      final changePct = prevClose != 0 ? (change / prevClose) * 100 : 0.0;

      return StockQuote(
        symbol: (meta['symbol'] as String?) ?? symbol,
        name: (meta['shortName'] as String?) ??
            (meta['longName'] as String?) ??
            symbol,
        price: price,
        change: change,
        changePercent: changePct,
        currency: (meta['currency'] as String?) ?? 'USD',
        closes: closes,
        previousClose: prevClose,
      );
    } catch (_) {
      return null;
    }
  }

  /// Convenience: resolve + fetch in one call.
  Future<StockQuote?> lookup(String query) async {
    final symbol = await resolveSymbol(query);
    if (symbol == null) return null;
    return fetchQuote(symbol);
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
