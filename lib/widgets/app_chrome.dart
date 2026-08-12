import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCE3E6B), AppColors.brandStrong],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(Icons.pets_rounded, size: size * 0.62, color: Colors.white),
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 8),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appColors;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppGradients.brandSoft(context),
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Icon(
              icon,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class AppStatusDot extends StatelessWidget {
  const AppStatusDot({super.key, required this.online, this.showLabel = true});

  final bool online;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.successBright : context.appColors.inkMuted;
    return Semantics(
      label: online ? '后端在线' : '后端离线',
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (showLabel) ...[
                const SizedBox(width: 8),
                Text(
                  online ? '在线' : '离线',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.appColors.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
