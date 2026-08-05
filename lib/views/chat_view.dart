import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/chat_provider.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ChatProvider>(builder: (context, cp, _) {
      return Column(children: [
        AppBar(title: const Text('对话'), centerTitle: true, backgroundColor: theme.colorScheme.surface, elevation: 0),
        Expanded(child: _buildMessages(cp, theme)),
        if (cp.responding)
          Container(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8), const Text('思考中…', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Spacer(),
              GestureDetector(onTap: () => cp.cancelResponse(),
                child: const Text('取消', style: TextStyle(fontSize: 12, color: Color(0xFFEF7A86)))),
            ])),
        _buildInputBar(cp, theme),
      ]);
    });
  }

  Widget _buildMessages(ChatProvider cp, ThemeData theme) {
    if (cp.loading) return const Center(child: CircularProgressIndicator());
    if (cp.turns.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_outlined, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 8),
        Text('和 AI 聊聊你的口味偏好', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
      ]));
    }
    return ListView.builder(controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: cp.turns.length,
      itemBuilder: (context, index) {
        final turn = cp.turns[index];
        final isError = turn.hasError;
        final hasResponse = turn.reply.isNotEmpty && turn.isDone;
        final userMessage = isError || turn.message.isEmpty ? null : turn.message;
        final errorText = isError ? (turn.message.isNotEmpty ? turn.message : '出错了，请重试') : null;

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (userMessage != null)
            Align(alignment: Alignment.centerRight, child: Container(
              margin: EdgeInsets.only(bottom: hasResponse ? 8 : 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFB7299),
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: const Radius.circular(4))),
              child: Text(userMessage, style: const TextStyle(color: Colors.white, fontSize: 14)))),
          if (hasResponse)
            Align(alignment: Alignment.centerLeft, child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: const Radius.circular(4))),
              child: MarkdownBody(
                data: turn.reply,
                selectable: true,
                shrinkWrap: true,
                onTapLink: (text, href, title) => _openLink(href),
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, height: 1.5),
                  listBullet: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                  code: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquote: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
                  a: const TextStyle(color: Color(0xFFFB7299), decoration: TextDecoration.underline),
                ),
              ))),
          if (errorText != null)
            Align(alignment: Alignment.centerLeft, child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF7A86).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16)),
              child: Text(errorText,
                style: const TextStyle(color: Color(0xFFEF7A86), fontSize: 14)))),
        ]);
      });
  }

  Widget _buildInputBar(ChatProvider cp, ThemeData theme) {
    return Container(padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(color: theme.colorScheme.surface, border: Border(top: BorderSide(color: Colors.grey[200]!))),
      child: SafeArea(top: false, child: Row(children: [
        Expanded(child: TextField(controller: _controller,
          textInputAction: TextInputAction.send,
          onSubmitted: (v) => _send(cp),
          decoration: InputDecoration(hintText: '说说你最近想看什么…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest))),
        const SizedBox(width: 8),
        IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFFFB7299)),
          onPressed: cp.responding ? null : () => _send(cp)),
      ])));
  }

  void _send(ChatProvider cp) {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;
    _controller.clear();
    cp.sendMessage(msg).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(_scrollController.position.maxScrollExtent + 100,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    });
  }

  void _openLink(String? href) {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
