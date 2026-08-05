import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../models/profile.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ProfileProvider>(builder: (context, pp, _) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的画像'), centerTitle: true, backgroundColor: theme.colorScheme.surface, elevation: 0),
        body: pp.loading
          ? const Center(child: CircularProgressIndicator())
          : pp.summary == null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.psychology_outlined, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('画像还在慢慢攒，先多看一阵。', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
              ]))
            : RefreshIndicator(onRefresh: () => pp.load(),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _buildPortrait(theme, pp),
                const SizedBox(height: 20),
                ...pp.summary!.layers.map((l) => _buildLayerTile(theme, l)),
                const Divider(height: 24),
                Text('兴趣领域', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...pp.summary!.interests.map((i) => _buildInterestChip(theme, i)),
                if (pp.summary!.avoidances.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('避雷方向', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFFEF7A86))),
                  const SizedBox(height: 8),
                  ...pp.summary!.avoidances.map((i) => _buildInterestChip(theme, i, avoid: true)),
                ],
                if (pp.probes.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('待确认的兴趣推测', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...pp.probes.map((p) => _buildProbeCard(context, theme, pp, p)),
                ],
                if (pp.notifications.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('通知', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...pp.notifications.map((n) => _buildNotificationCard(theme, n)),
                ],
                const SizedBox(height: 32),
              ])));
    });
  }

  Widget _buildPortrait(ThemeData theme, ProfileProvider pp) {
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFFB7299).withValues(alpha: 0.1), const Color(0xFF5AA9FF).withValues(alpha: 0.06)]),
        borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(
          color: const Color(0xFFFB7299), borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Text('🧠', style: TextStyle(fontSize: 24)))),
        const SizedBox(width: 16),
        Expanded(child: Text(pp.summary?.portrait ?? '画像还在慢慢攒…',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6))),
      ]));
  }

  Widget _buildLayerTile(ThemeData theme, ProfileLayer layer) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      Container(width: 4, height: 32, decoration: BoxDecoration(
        color: const Color(0xFFFB7299), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(layer.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (layer.summary.isNotEmpty) Text(layer.summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ])),
    ]));
  }

  Widget _buildInterestChip(ThemeData theme, ProfileInterest interest, {bool avoid = false}) {
    return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: avoid ? const Color(0xFFEF7A86).withValues(alpha: 0.08) : const Color(0xFF5AA9FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(interest.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          if (interest.reason.isNotEmpty) Text(interest.reason, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ])),
        if (interest.weight > 0)
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            child: Text('${(interest.weight * 100).toInt()}%', style: const TextStyle(fontSize: 11, color: Colors.grey))),
      ]));
  }

  Widget _buildProbeCard(BuildContext context, ThemeData theme, ProfileProvider pp, Map<String, dynamic> probe) {
    final domain = probe['domain'] ?? '';
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$domain', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(children: [
          _smallChip('是的', () => pp.respondToProbe(domain.toString(), 'confirm')),
          const SizedBox(width: 8),
          _smallChip('不是', () => pp.respondToProbe(domain.toString(), 'reject')),
        ]),
      ]));
  }

  Widget _buildNotificationCard(ThemeData theme, Map<String, dynamic> n) {
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF30B980).withValues(alpha: 0.08), const Color(0xFF5AA9FF).withValues(alpha: 0.08)]),
        borderRadius: BorderRadius.circular(12)),
      child: Text(n['message'] ?? n['reason'] ?? '', style: theme.textTheme.bodySmall));
  }

  Widget _smallChip(String label, VoidCallback? onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFFFB7299).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFFB7299)))));
  }
}
