import 'package:flutter/material.dart';
import '../device_recommender/device_profile.dart';
import '../device_recommender/model_catalogue.dart';

/// How well a model fits the current device's memory.
enum ModelFit { great, good, tight, tooBig }

/// Classifies a model against the device's memory budget.
///
/// We budget ~50% of total RAM as the safe ceiling for a model on iOS (apps
/// are jetsam-killed well below total RAM). This is stable, unlike free RAM.
ModelFit deviceFit(ModelVariant model, DeviceProfile device) {
  final budget = device.totalRamBytes * 0.5;
  final need = model.ramRequiredBytes.toDouble();
  if (need <= budget * 0.55) return ModelFit.great;
  if (need <= budget) return ModelFit.good;
  if (need <= budget * 1.3) return ModelFit.tight;
  return ModelFit.tooBig;
}

class FitBadge {
  const FitBadge(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

FitBadge fitBadge(ModelFit fit) => switch (fit) {
      ModelFit.great => const FitBadge(
          'Great fit', Color(0xFF22C55E), Icons.check_circle),
      ModelFit.good => const FitBadge(
          'Good fit', Color(0xFF22C55E), Icons.check_circle_outline),
      ModelFit.tight => const FitBadge(
          'Tight — may be slow', Color(0xFFF59E0B), Icons.warning_amber_rounded),
      ModelFit.tooBig => const FitBadge(
          'Too big for your device', Color(0xFFEF4444), Icons.error_outline),
    };

/// Short capability tags ("Chat", "Coding", "Vision"…) shown as chips.
/// Prefers a built-in model's curated [ModelVariant.strengths]; otherwise
/// infers from the name, family, flags and any Hugging Face [hfTags].
List<String> capabilityTags(ModelVariant model, {List<String> hfTags = const []}) {
  final tags = <String>{};
  final hay = ('${model.id} ${model.displayName} ${hfTags.join(' ')}').toLowerCase();

  if (model.isMultimodal || _has(hay, ['llava', 'minicpm-v', 'vision', 'vl', '-vl'])) {
    tags.add('Vision');
  }
  if (model.isReasoningModel || _has(hay, ['reason', 'r1', 'qwq', 'think', 'o1'])) {
    tags.add('Reasoning');
  }
  if (_has(hay, ['coder', 'code', 'starcoder', 'deepseek-coder'])) tags.add('Coding');
  if (_has(hay, ['math'])) tags.add('Math');
  if (_has(hay, ['instruct', 'chat', '-it', 'it-', 'sft'])) tags.add('Chat');

  if (model.parametersBillions > 0 && model.parametersBillions <= 2) {
    tags.add('Fast & light');
  } else if (model.parametersBillions >= 13) {
    tags.add('Most capable');
  }

  // Fold in a couple of curated strengths for built-in models.
  for (final s in model.strengths.take(2)) {
    if (s.length <= 18) tags.add(s);
  }

  if (tags.isEmpty) tags.add('General chat');
  return tags.take(4).toList();
}

bool _has(String haystack, List<String> needles) =>
    needles.any(haystack.contains);
