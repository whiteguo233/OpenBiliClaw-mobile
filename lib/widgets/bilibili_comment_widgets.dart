import 'package:flutter/material.dart';

import '../models/bilibili_interaction.dart';
import 'bilibili_video_layout.dart';
import 'cover_image.dart';

class BilibiliCommentTile extends StatelessWidget {
  const BilibiliCommentTile({
    super.key,
    required this.comment,
    required this.onOpenReplies,
  });
  final BilibiliComment comment;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BilibiliAvatar(url: comment.avatarUrl, name: comment.uname, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.uname,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  comment.message,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (comment.ctime > 0)
                      Text(
                        _commentTimeText(comment.ctime),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.thumb_up_outlined,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatBilibiliCount(comment.likeCount),
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: onOpenReplies,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('回复', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                if (comment.replies.isNotEmpty || comment.replyCount > 0)
                  Material(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: onOpenReplies,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final reply in comment.replies.take(2))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${reply.uname}：',
                                        style: TextStyle(color: colors.primary),
                                      ),
                                      TextSpan(text: reply.message),
                                    ],
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            Text(
                              '共 ${comment.replyCount > 0 ? comment.replyCount : comment.replies.length} 条回复 ›',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BilibiliAvatar extends StatelessWidget {
  const BilibiliAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 32,
  });
  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (url.trim().isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: colors.surfaceContainerHighest,
        child: Text(
          name.trim().isEmpty ? '?' : name.trim().characters.first,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: size * 0.4,
          ),
        ),
      );
    }
    return ClipOval(
      child: CoverImage(
        url: url,
        sourcePlatform: 'bilibili',
        width: size,
        height: size,
        borderRadius: size / 2,
      ),
    );
  }
}

class BilibiliCommentComposer extends StatefulWidget {
  const BilibiliCommentComposer({
    super.key,
    required this.hint,
    required this.onSubmit,
  });
  final String hint;

  /// Returns an inline error, or null after the comment has been published.
  final Future<String?> Function(String text) onSubmit;

  @override
  State<BilibiliCommentComposer> createState() =>
      _BilibiliCommentComposerState();
}

class _BilibiliCommentComposerState extends State<BilibiliCommentComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSubmit(text);
    } catch (_) {
      error = '评论发布失败，请稍后重试';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      _controller.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_busy,
                maxLength: 1000,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                style: TextStyle(color: colors.onSurface, fontSize: 14),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => IconButton(
                        tooltip: '发送',
                        color: colors.primary,
                        onPressed: value.text.trim().isEmpty ? null : _submit,
                        icon: const Icon(Icons.send_rounded, size: 22),
                      ),
                    ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              _error!,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

String _commentTimeText(int ctime) {
  final time = DateTime.fromMillisecondsSinceEpoch(ctime * 1000);
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  if (diff.inDays < 1) return '${diff.inHours}小时前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
