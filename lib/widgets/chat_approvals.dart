import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/custom_sources_api.dart';
import '../providers/chat_provider.dart';

/// Approval stays pending until the user explicitly accepts its stated impact.
class ChatApprovalsButton extends StatelessWidget {
  const ChatApprovalsButton({super.key});
  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    if (chat.approvals.isEmpty && chat.approvalError.isEmpty) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      key: const Key('chatApprovals'),
      icon: const Icon(Icons.fact_check_outlined),
      label: Text(
        chat.approvalError.isEmpty
            ? (chat.pendingApprovalCount > 0
                  ? '操作审批 · ${chat.pendingApprovalCount} 项待处理'
                  : '查看操作记录')
            : '审批连接异常 · 点击重试',
      ),
      onPressed: () {
        chat.loadApprovals();
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => ChangeNotifierProvider.value(
            value: chat,
            child: const _ApprovalsSheet(),
          ),
        );
      },
    );
  }
}

class _ApprovalsSheet extends StatelessWidget {
  const _ApprovalsSheet();
  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          ListTile(
            title: const Text('操作审批'),
            trailing: IconButton(
              tooltip: '关闭审批',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          if (chat.approvalError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(chat.approvalError),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final item in chat.approvals) _card(context, chat, item),
                if (chat.approvals.isEmpty)
                  const ListTile(title: Text('没有待审批操作')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    ChatProvider chat,
    Map<String, dynamic> item,
  ) {
    final id = item['approval_id']?.toString() ?? '';
    final pending = item['status'] == 'pending';
    final busy = chat.approvalBusy(id);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['summary']?.toString() ?? '待确认操作',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if ((item['impact'] ?? '').toString().isNotEmpty)
              Text(item['impact'].toString()),
            Text(sourceStatus(item['status'])),
            if ((item['result'] ?? '').toString().isNotEmpty)
              ExpansionTile(
                title: const Text('执行结果'),
                children: [SelectableText(item['result'].toString())],
              ),
            if ((item['error'] ?? '').toString().isNotEmpty)
              Text(item['error'].toString()),
            if (pending)
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    key: Key('approve-$id'),
                    onPressed: busy
                        ? null
                        : () => chat.decideApproval(id, approve: true),
                    child: Text(busy ? '提交中…' : '批准执行'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => chat.decideApproval(
                            id,
                            approve: false,
                            reason: '用户在原生 APP 拒绝',
                          ),
                    child: const Text('拒绝'),
                  ),
                ],
              ),
            if (item['status'] == 'executing') const Text('后台正在执行，完成后会自动更新。'),
          ],
        ),
      ),
    );
  }
}
