import 'dart:math';

/// Lightweight, on-device document retrieval. Splits a long document into
/// overlapping chunks and returns the chunks most relevant to a question using
/// a TF-IDF-style keyword score (BM25-lite). No embeddings or network needed.
class DocumentRetrievalService {
  DocumentRetrievalService({
    this.chunkSize = 700,
    this.overlap = 120,
    this.topK = 5,
  });

  /// Target characters per chunk.
  final int chunkSize;

  /// Characters of overlap between adjacent chunks (preserves context).
  final int overlap;

  /// How many chunks to return.
  final int topK;

  static const _stopwords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be',
    'been', 'to', 'of', 'in', 'on', 'for', 'with', 'as', 'at', 'by', 'this',
    'that', 'it', 'from', 'what', 'which', 'who', 'how', 'why', 'when', 'where',
    'do', 'does', 'did', 'can', 'could', 'would', 'should', 'i', 'you', 'me',
    'my', 'your', 'about', 'tell', 'give', 'please', 'explain', 'summarize',
  };

  /// Returns the most relevant excerpts of [document] for [question], joined
  /// with separators. If the document is short, returns it unchanged.
  String relevantContext(String document, String question) {
    final doc = document.trim();
    if (doc.length <= chunkSize * 2) return doc; // short enough to send whole

    final chunks = _chunk(doc);
    final queryTerms = _terms(question);
    if (queryTerms.isEmpty) {
      // No usable query terms — fall back to the document head.
      return doc.length > chunkSize * topK
          ? '${doc.substring(0, chunkSize * topK)}…'
          : doc;
    }

    // Document frequency for IDF.
    final df = <String, int>{};
    final chunkTerms = chunks.map(_terms).toList();
    for (final terms in chunkTerms) {
      for (final t in terms.toSet()) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    final n = chunks.length;

    // Score each chunk.
    final scored = <_Scored>[];
    for (var i = 0; i < chunks.length; i++) {
      final terms = chunkTerms[i];
      if (terms.isEmpty) continue;
      final tf = <String, int>{};
      for (final t in terms) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      var score = 0.0;
      for (final q in queryTerms) {
        final f = tf[q];
        if (f == null) continue;
        final idf = log(1 + n / (1 + (df[q] ?? 0)));
        // BM25-lite saturation on term frequency.
        score += idf * (f * 2.0) / (f + 1.0);
      }
      if (score > 0) scored.add(_Scored(i, score));
    }

    if (scored.isEmpty) {
      return doc.length > chunkSize * topK
          ? '${doc.substring(0, chunkSize * topK)}…'
          : doc;
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final picked = scored.take(topK).toList()
      ..sort((a, b) => a.index.compareTo(b.index)); // restore reading order

    return picked.map((s) => chunks[s.index].trim()).join('\n…\n');
  }

  List<String> _chunk(String text) {
    final chunks = <String>[];
    var start = 0;
    final step = max(1, chunkSize - overlap);
    while (start < text.length) {
      final end = min(start + chunkSize, text.length);
      chunks.add(text.substring(start, end));
      if (end >= text.length) break;
      start += step;
    }
    return chunks;
  }

  List<String> _terms(String s) {
    return s
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 2 && !_stopwords.contains(w))
        .toList();
  }
}

class _Scored {
  const _Scored(this.index, this.score);
  final int index;
  final double score;
}
