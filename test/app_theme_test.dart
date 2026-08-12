import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';

void main() {
  group('adaptive theme contrast', () {
    test('light semantic text colors meet WCAG AA', () {
      final theme = AppTheme.light();
      final palette = theme.extension<AppPalette>()!;

      _expectContrast(palette.ink, palette.surface, 4.5, 'primary text');
      _expectContrast(palette.inkMuted, palette.surface, 4.5, 'body text');
      _expectContrast(
        theme.colorScheme.primary,
        palette.background,
        4.5,
        'brand text',
      );
      _expectContrast(
        theme.colorScheme.primary,
        palette.brandSoft,
        4.5,
        'brand text on tonal surface',
      );
      _expectContrast(
        theme.colorScheme.secondary,
        palette.lavenderSoft,
        4.5,
        'secondary text',
      );
      _expectContrast(
        theme.colorScheme.primary,
        theme.colorScheme.onPrimary,
        4.5,
        'filled primary control',
      );
      _expectContrast(AppColors.success, palette.surface, 4.5, 'success');
      _expectContrast(theme.colorScheme.error, palette.surface, 4.5, 'error');
    });

    test('dark semantic text colors meet WCAG AA', () {
      final theme = AppTheme.dark();
      final palette = theme.extension<AppPalette>()!;

      _expectContrast(palette.ink, palette.surface, 4.5, 'primary text');
      _expectContrast(palette.inkMuted, palette.surface, 4.5, 'body text');
      _expectContrast(
        theme.colorScheme.primary,
        palette.background,
        4.5,
        'brand text',
      );
      _expectContrast(
        theme.colorScheme.primary,
        palette.brandSoft,
        4.5,
        'brand text on tonal surface',
      );
      _expectContrast(
        theme.colorScheme.secondary,
        palette.lavenderSoft,
        4.5,
        'secondary text',
      );
      _expectContrast(
        theme.colorScheme.primary,
        theme.colorScheme.onPrimary,
        4.5,
        'filled primary control',
      );
      _expectContrast(AppColors.successDark, palette.surface, 4.5, 'success');
      _expectContrast(theme.colorScheme.error, palette.surface, 4.5, 'error');
    });
  });
}

void _expectContrast(
  Color foreground,
  Color background,
  double minimum,
  String label,
) {
  final ratio = _contrastRatio(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$label contrast was ${ratio.toStringAsFixed(2)}:1',
  );
}

double _contrastRatio(Color first, Color second) {
  final lighter = math.max(first.computeLuminance(), second.computeLuminance());
  final darker = math.min(first.computeLuminance(), second.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}
