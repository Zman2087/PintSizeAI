// test/features/device_recommender/model_recommender_test.dart
//
// Pure Dart tests — no Flutter dependency, no platform channel.
// Run with: flutter test test/features/device_recommender/

import 'package:flutter_test/flutter_test.dart';
import 'package:pintsize_ai/features/device_recommender/device_profile.dart';
import 'package:pintsize_ai/features/device_recommender/model_catalogue.dart';
import 'package:pintsize_ai/features/device_recommender/model_recommender.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

DeviceProfile makeProfile({
  required int totalRamGb,
  required int freeRamGb,
  required int freeStorageGb,
  required ChipTier chipTier,
  bool hasGpu = true,
  int cpuCoreCount = 6,
}) {
  return DeviceProfile(
    totalRamBytes:    totalRamGb    * 1024 * 1024 * 1024,
    freeRamBytes:     freeRamGb     * 1024 * 1024 * 1024,
    freeStorageBytes: freeStorageGb * 1024 * 1024 * 1024,
    chipTier:         chipTier,
    cpuCoreCount:     cpuCoreCount,
    hasGpuAcceleration: hasGpu,
    osVersion:        '18.0',
    deviceName:       'Test Device',
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  const recommender = ModelRecommender();

  group('iPhone 16 Pro — flagship, 8GB RAM', () {
    final device = makeProfile(
      totalRamGb: 8, freeRamGb: 7, freeStorageGb: 50,
      chipTier: ChipTier.flagship,
    );

    test('recommends a flagship-tier model and 8B models still fit', () {
      final rec = recommender.recommend(device);
      // Since Qwen 3.5 (2026), a 4B multimodal model legitimately outranks
      // the 2024 7–8B generation on quality × speed × headroom, so the
      // recommendation floor is 4B — but a flagship must still be *able*
      // to run the 8B tier (i.e. it must rank, not be ruled out).
      expect(rec.recommended.parametersBillions, greaterThanOrEqualTo(4.0));
      expect(
        rec.allRanked.where(
          (r) => r.model.parametersBillions >= 7.0 && r.fitsInRam,
        ),
        isNotEmpty,
      );
    });

    test('estimated speed is above the minimum floor', () {
      final rec = recommender.recommend(device);
      expect(rec.estimatedTokensPerSec, greaterThanOrEqualTo(ModelRecommender.kMinTokensPerSec));
    });

    test('reason summary mentions flagship', () {
      final rec = recommender.recommend(device);
      expect(rec.reasonSummary.toLowerCase(), contains('flagship'));
    });
  });

  group('Samsung Galaxy S23 — highEnd, 8GB RAM', () {
    final device = makeProfile(
      totalRamGb: 8, freeRamGb: 4, freeStorageGb: 30,
      chipTier: ChipTier.highEnd,
    );

    test('recommends a model that fits in 4GB free RAM', () {
      final rec = recommender.recommend(device);
      expect(
        rec.recommended.ramRequiredBytes,
        lessThanOrEqualTo(device.safeModelRamBytes),
      );
    });

    test('estimated speed is above the minimum floor', () {
      final rec = recommender.recommend(device);
      expect(rec.estimatedTokensPerSec, greaterThanOrEqualTo(ModelRecommender.kMinTokensPerSec));
    });
  });

  group('Mid-range Android — 6GB RAM, 4GB free', () {
    final device = makeProfile(
      totalRamGb: 6, freeRamGb: 4, freeStorageGb: 15,
      chipTier: ChipTier.midRange,
    );

    test('does not recommend a 7B model', () {
      final rec = recommender.recommend(device);
      // 7B Q4_K_M needs ~5GB — should not be recommended on 4GB free
      expect(rec.recommended.parametersBillions, lessThan(7.0));
    });

    test('recommended model RAM fits safely', () {
      final rec = recommender.recommend(device);
      expect(
        rec.recommended.ramRequiredBytes,
        lessThanOrEqualTo(device.safeModelRamBytes),
      );
    });
  });

  group('Entry-level phone — 4GB RAM, 2GB free', () {
    final device = makeProfile(
      totalRamGb: 4, freeRamGb: 2, freeStorageGb: 8,
      chipTier: ChipTier.entry,
    );

    test('recommends a small model under 2GB', () {
      final rec = recommender.recommend(device);
      expect(rec.recommended.fileSizeBytes, lessThan(2100000000));
    });

    test('7B models are ruled out', () {
      final rec = recommender.recommend(device);
      final ruled7b = rec.ruledOut
          .where((r) => r.model.parametersBillions >= 7.0)
          .toList();
      expect(ruled7b, isNotEmpty);
    });
  });

  group('Very old device — ChipTier.tooSlow', () {
    final device = makeProfile(
      totalRamGb: 2, freeRamGb: 1, freeStorageGb: 4,
      chipTier: ChipTier.tooSlow,
    );

    test('returns a result (does not throw)', () {
      final rec = recommender.recommend(device);
      expect(rec, isNotNull);
    });

    test('recommends the smallest model in the catalogue', () {
      final rec = recommender.recommend(device);
      expect(rec.recommended.id, equals(kModelCatalogue.first.id));
    });
  });

  group('Ample RAM but CPU-only (no GPU)', () {
    final device = makeProfile(
      totalRamGb: 8, freeRamGb: 6, freeStorageGb: 30,
      chipTier: ChipTier.highEnd,
      hasGpu: false,
    );

    test('recommends a smaller model than the GPU equivalent', () {
      final gpuDevice = makeProfile(
        totalRamGb: 8, freeRamGb: 6, freeStorageGb: 30,
        chipTier: ChipTier.highEnd,
        hasGpu: true,
      );
      final cpuRec = recommender.recommend(device);
      final gpuRec = recommender.recommend(gpuDevice);
      // CPU-only eliminates larger models due to speed floor, so recommended model is smaller
      expect(
        cpuRec.recommended.parametersBillions,
        lessThan(gpuRec.recommended.parametersBillions),
      );
    });
  });

  group('Not enough storage', () {
    final device = makeProfile(
      totalRamGb: 8, freeRamGb: 5, freeStorageGb: 1, // only 1GB free
      chipTier: ChipTier.flagship,
    );

    test('only recommends models that fit in available storage', () {
      final rec = recommender.recommend(device);
      expect(
        rec.recommended.fileSizeBytes,
        lessThanOrEqualTo(device.freeStorageBytes),
      );
    });

    test('large models are in ruled-out list with storage reason', () {
      final rec = recommender.recommend(device);
      final storageRuled = rec.ruledOut
          .where((r) => r.reason == EliminationReason.notEnoughStorage)
          .toList();
      expect(storageRuled, isNotEmpty);
    });
  });

  group('Scoring sanity checks', () {
    test('allRanked is ordered best-first', () {
      final device = makeProfile(
        totalRamGb: 8, freeRamGb: 6, freeStorageGb: 30,
        chipTier: ChipTier.flagship,
      );
      final rec = recommender.recommend(device);
      for (var i = 0; i < rec.allRanked.length - 1; i++) {
        expect(rec.allRanked[i].score, greaterThanOrEqualTo(rec.allRanked[i + 1].score));
      }
    });

    test('recommended model is the first in allRanked', () {
      final device = makeProfile(
        totalRamGb: 8, freeRamGb: 6, freeStorageGb: 30,
        chipTier: ChipTier.flagship,
      );
      final rec = recommender.recommend(device);
      expect(rec.allRanked.first.model.id, equals(rec.recommended.id));
    });
  });
}
