import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/app_theme.dart';

/// Unified message inbox aligned with the web / extension clients: interest
/// probes, avoidance probes, cognition notifications and pending chat
/// confirmations in one bottom sheet, opened from the top-bar bell.
class MessageInbox extends StatefulWidget {
  const MessageInbox({super.key});

  /// Open the inbox as a modal bottom sheet. Returns once dismissed.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MessageInbox(),
    );
  }

  @override
  State<MessageInbox> createState() => _MessageInboxState();
}

class _MessageInboxState extends State<MessageInbox> {
  @override
  void initState() {
    super.initState();
    // Refresh probe / cognition / pending state each time the inbox opens so
    // the badge count and the sheet stay in sync (mirrors the web clients'
    // loadNotifications on bell click).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = context.read<ProfileProvider>();
      final chat = context.read<ChatProvider>();
      unawaited(profile.loadNotifications());
      unawaited(chat.loadPendingConfirmations());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Consumer2<ProfileProvider, ChatProvider>(
        builder: (context, profile, chat, _) {
          final probes = profile.probes;
          final avoidanceProbes = profile.avoidanceProbes;
          final cognition = profile.cognitionNotification;
          final pending = chat.pendingConfirmations;
          final hasAny =
              probes.isNotEmpty ||
              avoidanceProbes.isNotEmpty ||
              cognition != null ||
              pending.isNotEmpty;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                child: Row(
                  children: [
                    Text('消息', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: hasAny
                    ? ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                        children: [
                          if (probes.isNotEmpty)
                            _ProbeSection(
                              title: '兴趣探测',
                              icon: Icons.travel_explore_rounded,
                              color: const Color(0xFF5AA9FF),
                              probes: probes,
                              avoidance: false,
                              onChat: (domain) =>
                                  _startChat('probe', domain, domain),
                            ),
                          if (avoidanceProbes.isNotEmpty)
                            _ProbeSection(
                              title: '避雷探针',
                              icon: Icons.shield_outlined,
                              color: const Color(0xFFEF7A86),
                              probes: avoidanceProbes,
                              avoidance: true,
                              onChat: (domain) =>
                                  _startChat('avoidance_probe', domain, domain),
                            ),
                          if (cognition != null)
                            _CognitionCard(notification: cognition),
                          if (pending.isNotEmpty)
                            _PendingConfirmations(items: pending),
                        ],
                      )
                    : const _EmptyInbox(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _startChat(String scope, String subjectId, String subjectTitle) {
    Navigator.pop(context);
    context.read<ChatProvider>().startContextualChat(
      scope,
      subjectId,
      subjectTitle,
    );
    // The chat tab is selected by HomeView via a callback; the provider
    // change notifies listeners so the tab switch can observe it.
  }
}

class _ProbeSection extends StatelessWidget {
  const _ProbeSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.probes,
    required this.avoidance,
    required this.onChat,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> probes;
  final bool avoidance;
  final void Function(String domain) onChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, title, icon, color),
        ...probes.map((probe) {
          final domain = probe['domain']?.toString() ?? '';
          return _probeCard(context, probe, domain);
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _probeCard(
    BuildContext context,
    Map<String, dynamic> probe,
    String domain,
  ) {
    final theme = Theme.of(context);
    final challenge = probe['challenge'] == true;
    final reason = probe['reason']?.toString() ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  challenge ? '挑战探针' : (avoidance ? '避雷确认' : '兴趣探测'),
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  domain,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(reason, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonal(
                onPressed: () => _respond(context, probe, domain, 'confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.12),
                  foregroundColor: color,
                ),
                child: Text(avoidance ? '确认避雷' : '确认喜欢'),
              ),
              OutlinedButton(
                onPressed: () => _respond(context, probe, domain, 'defer'),
                child: Text(avoidance ? '搁置避雷' : '暂时搁置'),
              ),
              TextButton(
                onPressed: () => _respond(context, probe, domain, 'reject'),
                child: Text(avoidance ? '不是雷点' : '确认不喜欢'),
              ),
              TextButton.icon(
                onPressed: () => onChat(domain),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('多聊聊'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    Map<String, dynamic> probe,
    String domain,
    String action,
  ) async {
    final profile = context.read<ProfileProvider>();
    final ok = avoidance
        ? await profile.respondToAvoidanceProbe(domain, action)
        : await profile.respondToProbe(domain, action);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(profile.error),
            backgroundColor: Colors.red[700],
          ),
        );
    }
  }

  Widget _sectionTitle(
    ThemeData theme,
    String title,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CognitionCard extends StatelessWidget {
  const _CognitionCard({required this.notification});

  final Map<String, dynamic> notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = notification['summary']?.toString() ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF30B980).withValues(alpha: 0.1),
            const Color(0xFF5AA9FF).withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF30B980)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '画像有一条新认知',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(summary, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<ProfileProvider>().markCognitionSeen();
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _PendingConfirmations extends StatelessWidget {
  const _PendingConfirmations({required this.items});

  final List<PendingConfirmation> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Icon(
                Icons.pending_actions_rounded,
                size: 17,
                color: AppColors.lavender,
              ),
              const SizedBox(width: 6),
              Text(
                '待聊确认',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        ...items.map(
          (item) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.observation.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.observation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () {
                    final chat = context.read<ChatProvider>();
                    unawaited(chat.openPendingConfirmation(item));
                    Navigator.pop(context);
                  },
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 44,
              color: Colors.grey,
            ),
            SizedBox(height: 10),
            Text('暂时没有新消息', style: TextStyle(color: Colors.grey, fontSize: 14)),
            SizedBox(height: 2),
            Text(
              '兴趣探测、避雷探针和待聊确认会在这里出现',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
