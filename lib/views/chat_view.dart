import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat.dart';
import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chrome.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _tailSignature = '';

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final turns = provider.turns;
        _scheduleHistoryScroll(turns);
        return Column(
          children: [
            AppPageHeader(
              icon: Icons.chat_bubble_rounded,
              title: '和阿B聊聊',
              subtitle: '${turns.length} 条共享记录 · 你的判断会在这里沉淀',
              trailing: IconButton(
                tooltip: '刷新共享历史',
                onPressed: provider.loading ? null : provider.loadTurns,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            if (provider.pendingCount > 0) _pendingPanel(context, provider),
            if (provider.error.isNotEmpty) _errorBanner(context, provider),
            if (provider.dialogueContext != null)
              _dialogueContextBar(context, provider)
            else if (provider.composeContext.active)
              _composeContextBar(context, provider),
            Expanded(child: _buildMessages(context, provider, theme, turns)),
            if (provider.responding) _thinkingBar(provider),
            _buildInputBar(provider),
          ],
        );
      },
    );
  }

  Widget _pendingPanel(BuildContext context, ChatProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.lavender.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.pending_actions_rounded,
            size: 20,
            color: AppColors.lavender,
          ),
        ),
        title: Text('待聊确认（${provider.pendingCount}）'),
        subtitle: const Text('来自插件、桌面端和后台认知的共享工作列表'),
        children: provider.pendingConfirmations
            .map((item) => _pendingItem(context, provider, item))
            .toList(),
      ),
    );
  }

  Widget _pendingItem(
    BuildContext context,
    ChatProvider provider,
    PendingConfirmation item,
  ) {
    final busy = provider.confirmationBusy(item.ref);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _scopeChip(item.kind == 'confusion' ? '疑惑' : '阿B 的猜测'),
                const Spacer(),
                if (item.confidence > 0)
                  Text(
                    '置信 ${(item.confidence * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (item.observation.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                item.observation,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () => _openConfirmation(context, provider, item),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.forum_outlined, size: 16),
                label: const Text('放进对话'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, ChatProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(provider.error, style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            onPressed: provider.clearError,
            icon: const Icon(Icons.close, size: 17),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _dialogueContextBar(BuildContext context, ChatProvider provider) {
    final selected = provider.dialogueContext!;
    return _contextBar(
      context,
      label: selected.kind == 'confusion' ? '正在回复疑惑' : '正在回复阿B 的猜测',
      title: selected.title,
      onClear: provider.clearDialogueContext,
    );
  }

  Widget _composeContextBar(BuildContext context, ChatProvider provider) {
    final selected = provider.composeContext;
    final label = switch (selected.scope) {
      'delight' => '正在聊惊喜推荐',
      'probe' => '正在聊兴趣探测',
      'avoidance_probe' => '正在聊避雷探测',
      _ => '上下文对话',
    };
    return _contextBar(
      context,
      label: label,
      title: selected.subjectTitle,
      onClear: provider.clearComposeContext,
    );
  }

  Widget _contextBar(
    BuildContext context, {
    required String label,
    required String title,
    required VoidCallback onClear,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: const Color(0xFFFB7299).withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18, color: Color(0xFFFB7299)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('清除')),
        ],
      ),
    );
  }

  Widget _buildMessages(
    BuildContext context,
    ChatProvider provider,
    ThemeData theme,
    List<ChatTurn> turns,
  ) {
    if (provider.loading && turns.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (turns.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.loadTurns,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_outlined, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text(
                    '和 AI 聊聊你的口味、猜测和疑惑',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: provider.loadTurns,
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        itemCount: turns.length,
        itemBuilder: (context, index) {
          final turn = turns[turns.length - index - 1];
          if (turn.isCard || turn.isQuestion) {
            return _dialogueCard(context, provider, turn);
          }
          return _messageTurn(context, provider, turn, theme);
        },
      ),
    );
  }

  Widget _messageTurn(
    BuildContext context,
    ChatProvider provider,
    ChatTurn turn,
    ThemeData theme,
  ) {
    final hasResponse = turn.reply.isNotEmpty && turn.isDone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (turn.replyToTurnId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 4),
            child: Text('↪ 回复一条确认上下文', style: theme.textTheme.labelSmall),
          ),
        if (turn.scope != 'chat')
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _scopeChip(_scopeLabel(turn.scope)),
            ),
          ),
        if (turn.message.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: EdgeInsets.only(bottom: hasResponse ? 8 : 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.brand, AppColors.brandStrong],
                ),
                borderRadius: BorderRadius.circular(
                  18,
                ).copyWith(bottomRight: const Radius.circular(4)),
              ),
              child: Text(
                turn.message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        if (hasResponse)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(
                  18,
                ).copyWith(bottomLeft: const Radius.circular(4)),
                border: Border.all(color: AppColors.line),
              ),
              child: _markdown(theme, turn.reply),
            ),
          )
        else if (turn.isPending)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('后台处理中…', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        if (turn.hasError)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF7A86).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    turn.error.isNotEmpty ? turn.error : '出错了，请重试',
                    style: const TextStyle(color: Color(0xFFEF7A86)),
                  ),
                  TextButton(
                    onPressed: () {
                      _controller.text = turn.message;
                      _controller.selection = TextSelection.collapsed(
                        offset: _controller.text.length,
                      );
                    },
                    child: const Text('放回输入框'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _dialogueCard(
    BuildContext context,
    ChatProvider provider,
    ChatTurn turn,
  ) {
    final busy = provider.cardBusy(turn.turnId);
    final title = turn.cardTitle.isNotEmpty ? turn.cardTitle : turn.message;
    final isQuestion = turn.isQuestion || turn.cardKind == 'confusion';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isQuestion
              ? [
                  const Color(0xFF5AA9FF).withValues(alpha: 0.12),
                  const Color(0xFF30B980).withValues(alpha: 0.06),
                ]
              : [
                  const Color(0xFFFB7299).withValues(alpha: 0.12),
                  const Color(0xFF5AA9FF).withValues(alpha: 0.06),
                ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color:
              (isQuestion ? const Color(0xFF5AA9FF) : const Color(0xFFFB7299))
                  .withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _scopeChip(isQuestion ? '待厘清的疑惑' : '阿B 的猜测'),
              const Spacer(),
              if (turn.cardState.isNotEmpty)
                Text(
                  _cardStateLabel(turn.cardState),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (turn.evidence.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              dense: true,
              title: Text('依据 ${turn.evidence.length} 条'),
              children: turn.evidence
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(
                            child: Text(
                              item,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 8),
          if (turn.cardTerminal)
            Text(
              '这条已处理：${_cardStateLabel(turn.cardState)}',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (isQuestion)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () => provider.selectDialogueContext(turn.turnId),
                icon: const Icon(Icons.reply, size: 16),
                label: const Text('聊清楚'),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  (turn.cardActions.isEmpty
                          ? const ['confirm', 'reject', 'discuss', 'defer']
                          : turn.cardActions)
                      .map(
                        (action) => OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => provider.actOnCard(turn, action),
                          child: Text(_cardActionLabel(action)),
                        ),
                      )
                      .toList(),
            ),
          if (busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _thinkingBar(ChatProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          const Text(
            '正在等待共享后端回复…',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Spacer(),
          TextButton(
            onPressed: provider.cancelResponse,
            child: const Text('停止等待'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatProvider provider) {
    final subject =
        provider.dialogueContext?.title ??
        (provider.composeContext.active
            ? provider.composeContext.subjectTitle
            : '');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(provider),
              decoration: InputDecoration(
                hintText: subject.isEmpty ? '说说你最近想看什么…' : '聊聊「$subject」…',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                fillColor: AppColors.surfaceMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '发送',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: AppColors.brandStrong,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.brandSoft,
            ),
            icon: const Icon(Icons.arrow_upward_rounded, size: 22),
            onPressed: provider.responding ? null : () => _send(provider),
          ),
        ],
      ),
    );
  }

  Widget _markdown(ThemeData theme, String value) {
    return MarkdownBody(
      data: value,
      selectable: true,
      shrinkWrap: true,
      onTapLink: (_, href, _) => _openLink(href),
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 14,
          height: 1.5,
        ),
        code: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 13,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          fontFamily: 'monospace',
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        a: const TextStyle(
          color: Color(0xFFFB7299),
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _scopeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  String _scopeLabel(String scope) {
    return switch (scope) {
      'delight' => '惊喜推荐',
      'probe' => '兴趣探测',
      'avoidance_probe' => '避雷探测',
      'hypothesis' => '猜测卡',
      'confusion' => '疑惑',
      _ => scope,
    };
  }

  String _cardActionLabel(String action) {
    return switch (action) {
      'confirm' => '说得准',
      'reject' => '不准确',
      'discuss' => '聊一聊',
      'defer' => '先放一放',
      _ => action,
    };
  }

  String _cardStateLabel(String state) {
    return switch (state) {
      'confirmed' => '已确认',
      'rejected' => '已否认',
      'deferred' => '已暂缓',
      'revised' => '已修正',
      'processing' => '处理中',
      'retryable_error' => '可重试',
      _ => state,
    };
  }

  Future<void> _openConfirmation(
    BuildContext context,
    ChatProvider provider,
    PendingConfirmation item,
  ) async {
    final ok = await provider.openPendingConfirmation(item);
    if (!context.mounted || !ok) return;
    _scrollToBottom();
  }

  Future<void> _send(ChatProvider provider) async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    _controller.clear();
    _scrollToBottom();
    final ok = await provider.sendMessage(message);
    if (!ok && mounted && _controller.text.isEmpty) {
      _controller.text = message;
      _controller.selection = TextSelection.collapsed(offset: message.length);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _scheduleHistoryScroll(List<ChatTurn> turns) {
    if (turns.isEmpty) return;
    final tail = turns.last;
    final signature = [
      tail.turnId,
      tail.status,
      tail.reply.length,
      tail.cardState,
    ].join('|');
    final initial = _tailSignature.isEmpty;
    final changed = signature != _tailSignature;
    if (!initial && !changed) return;

    final shouldFollow =
        initial ||
        !_scrollController.hasClients ||
        (_scrollController.position.pixels -
                    _scrollController.position.minScrollExtent)
                .abs() <
            240;
    _tailSignature = signature;
    if (!shouldFollow || initial) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openLink(String? href) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
