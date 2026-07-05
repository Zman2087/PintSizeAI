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
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
    },
  ));

  /// Heuristic: does this message look like a stock-price question?
  static bool looksLikeStockQuery(String text) {
    final lower = text.toLowerCase();
    const triggers = [
      'stock',
      'share price',
      'shares',
      'ticker',
      'nasdaq',
      'nyse',
      'market cap',
      'how much is',
      'price of',
      '\$',
      'trading at',
      'stock price',
      'price for',
      'worth right now',
      'share value',
      'quote for',
      'market price',
    ];
    return triggers.any(lower.contains);
  }

  // Filler words stripped from a question to isolate the company/ticker.
  static const _fillers = {
    'what',
    'whats',
    "what's",
    'is',
    'the',
    'a',
    'share',
    'shares',
    'price',
    'prices',
    'stock',
    'stocks',
    'current',
    'currently',
    'trading',
    'trade',
    'just',
    'list',
    'show',
    'or',
    'me',
    'please',
    'value',
    'worth',
    'quote',
    'for',
    'of',
    'on',
    'at',
    'how',
    'much',
    'does',
    'cost',
    'today',
    'now',
    'latest',
    'give',
    'tell',
    'to',
    'and',
    'get',
    'find',
    'my',
    'market',
    'ticker',
  };

  /// Strips filler words so only the company name / ticker remains.
  static String cleanQuery(String query) {
    final tokens = query
        .toLowerCase()
        // Remove apostrophes FIRST so "what's" -> "whats" (a filler) instead of
        // leaving a stray "s" that corrupts the search (e.g. "s spacex").
        .replaceAll(RegExp(r"['’`]"), '')
        .replaceAll(RegExp(r'[^a-z0-9\.\s]'), ' ')
        .split(RegExp(r'\s+'))
        // Drop fillers and any leftover single-character tokens.
        .where((t) => t.length > 1 && !_fillers.contains(t))
        .toList();
    return tokens.join(' ').trim();
  }

  /// Resolves a company name or ticker to a Yahoo symbol.
  Future<String?> resolveSymbol(String query) async {
    final cleaned = cleanQuery(query);
    if (cleaned.isEmpty) return null;

    // Try the cleaned phrase, then the same with an exchange suffix stripped
    // (e.g. "ghhf.asx" → "ghhf"), then a bare short ticker.
    final candidates = <String>[
      cleaned,
      cleaned.replaceAll(RegExp(r'\.(asx|ax|us|l|to|nasdaq|nyse|nse|hk)$'), ''),
    ];
    final seen = <String>{};
    for (final c in candidates) {
      if (c.isEmpty || !seen.add(c)) continue;
      final sym = await _searchOne(c);
      if (sym != null) return sym;
    }
    // Last resort: a bare short ticker typed directly.
    if (RegExp(r'^[a-z]{1,5}$').hasMatch(cleaned)) return cleaned.toUpperCase();
    return null;
  }

  // Names of leveraged / inverse / derivative products we should NOT return
  // when the user just asks for a company (e.g. "spacex" must be SPCX, not a
  // "GraniteShares 2x Short SpaceX" ETF or a "Ninepoint SpaceX HighShares ETF").
  static final _derivativeMarkers = RegExp(
      r'\b(2x|3x|1\.5x|-1x|ultra|ultrashort|leveraged|inverse|short|long|bull|bear|daily target|geared)\b',
      caseSensitive: false);
  // Fund/wrapper markers — these track a company but aren't the company itself.
  static final _fundMarkers = RegExp(
      r'\b(etf|etn|fund|trust|tokenized|highshares|notes)\b',
      caseSensitive: false);

  Future<String?> _searchOne(String q) async {
    try {
      final resp = await _dio.get(
        'https://query1.finance.yahoo.com/v1/finance/search',
        queryParameters: {'q': q, 'quotesCount': 8, 'newsCount': 0},
      );
      final quotes = (resp.data['quotes'] as List?) ?? [];
      String? best;
      var bestScore = -1 << 30;
      for (var i = 0; i < quotes.length; i++) {
        final m = quotes[i] as Map;
        final sym = m['symbol'] as String?;
        if (sym == null || sym.isEmpty) continue;
        final type = (m['quoteType'] as String?) ?? '';
        final name = '${m['shortname'] ?? ''} ${m['longname'] ?? ''}';

        // Base score by instrument type — prefer the actual company (EQUITY).
        var score = switch (type) {
          'EQUITY' => 100,
          'MUTUALFUND' => 55,
          'INDEX' => 45,
          'ETF' => 40,
          'CRYPTOCURRENCY' => 10,
          _ => 0,
        };
        // Heavily penalise leveraged/inverse products unless asked for.
        if (_derivativeMarkers.hasMatch(name) &&
            !_derivativeMarkers.hasMatch(q)) {
          score -= 80;
        }
        // Penalise fund/ETF wrappers unless the user explicitly asked for one —
        // "spacex" should resolve to the company (SPCX), not a "SpaceX ETF".
        if (_fundMarkers.hasMatch(name) && !_fundMarkers.hasMatch(q)) {
          score -= 70;
        }
        // Exact ticker match (ignoring any exchange suffix) is the strongest
        // signal — e.g. querying "SPY" should return SPY even though it's a fund.
        final bareSym = sym.split('.').first.toLowerCase();
        if (bareSym == q.toLowerCase()) {
          score += 80;
        } else if (name.toLowerCase().contains(q.toLowerCase())) {
          // Weak hint only; a wrapper's name often contains the company too.
          score += 8;
        }
        // Prefer a primary/US listing over a foreign secondary (e.g. SXHI.NE).
        if (sym.contains('.')) score -= 12;
        // Prefer earlier (more relevant) results on ties.
        score -= i;

        if (score > bestScore) {
          bestScore = score;
          best = sym;
        }
      }
      return best;
    } catch (_) {}
    return null;
  }

  /// Yahoo range/interval pairs for each selectable chart window.
  static const chartRanges = <String, ({String range, String interval})>{
    '1W': (range: '5d', interval: '1d'),
    '1M': (range: '1mo', interval: '1d'),
    '6M': (range: '6mo', interval: '1d'),
    '1Y': (range: '1y', interval: '1wk'),
    '5Y': (range: '5y', interval: '1wk'),
    '10Y': (range: '10y', interval: '1mo'),
  };

  /// Fetches just the close prices for [symbol] over a labelled window
  /// (one of [chartRanges]). Returns an empty list if unavailable.
  Future<List<double>> fetchCloses(String symbol, String rangeLabel) async {
    final r = chartRanges[rangeLabel] ?? chartRanges['1M']!;
    try {
      final resp = await _dio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}',
        queryParameters: {'range': r.range, 'interval': r.interval},
      );
      final result = (resp.data['chart']?['result'] as List?)?.firstOrNull;
      final indicators = result?['indicators']?['quote']?[0] as Map?;
      final rawCloses = (indicators?['close'] as List?) ?? const [];
      return rawCloses
          .where((e) => e != null)
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches a quote + [rangeLabel] of closes for [symbol].
  Future<StockQuote?> fetchQuote(String symbol,
      {String rangeLabel = '1M'}) async {
    final r =
        StockService.chartRanges[rangeLabel] ?? StockService.chartRanges['1M']!;
    try {
      final resp = await _dio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}',
        queryParameters: {'range': r.range, 'interval': r.interval},
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
