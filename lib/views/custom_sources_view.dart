import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/custom_sources_api.dart';
import 'source_login_view.dart';

class CustomSourcesView extends StatefulWidget {
  const CustomSourcesView({super.key, required this.api});
  final CustomSourcesApi api;
  @override
  State<CustomSourcesView> createState() => _CustomSourcesViewState();
}

class _CustomSourcesViewState extends State<CustomSourcesView> {
  List<Map<String, dynamic>> _items = [], _executors = [];
  String _error = '';
  bool _loading = false;
  final Set<String> _busy = {};
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data = await widget.api.list();
      if (!mounted) return;
      setState(() {
        _items = sourceMaps(data['items']);
        _executors = sourceMaps(data['executors']);
        _error = '';
      });
      _timer?.cancel();
      if (_executors.any((e) => e['setup_state'] == 'preparing')) {
        _timer = Timer(const Duration(seconds: 3), _load);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '来源加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '操作未完成：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _edit(Map<String, dynamic> source) async {
    final name = TextEditingController(text: source['name']?.toString() ?? '');
    final share = TextEditingController(text: '${source['target_share'] ?? 1}');
    final interval = TextEditingController(
      text: '${source['interval_minutes'] ?? 30}',
    );
    final key = GlobalKey<FormState>();
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('来源设置'),
        content: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('sourceNameInput'),
                  controller: name,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: '来源名称'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? '请输入名称' : null,
                ),
                TextFormField(
                  key: const Key('sourceShareInput'),
                  controller: share,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '候选池占比（份）'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 20 ? '请输入 1–20 的整数' : null;
                  },
                ),
                TextFormField(
                  key: const Key('sourceIntervalInput'),
                  controller: interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '发现间隔（分钟）'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 5 || n > 10080
                        ? '请输入 5–10080 的整数'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(dialog, {
                  'name': name.text.trim(),
                  'target_share': int.parse(share.text),
                  'interval_minutes': int.parse(interval.text),
                });
              }
            },
            child: const Text('保存来源设置'),
          ),
        ],
      ),
    );
    // Dispose after the dialog's exit animation has released its fields.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    share.dispose();
    interval.dispose();
    if (values != null && mounted) {
      await _perform(source['source_id'].toString(), () async {
        await widget.api.update(source['source_id'].toString(), values);
      });
    }
  }

  Future<void> _login(String id) async {
    final draft = await widget.api.login(id);
    final draftId = draft['draft_id']?.toString() ?? '';
    if (draftId.isEmpty) throw const FormatException('未返回登录草稿，请重试');
    if (!mounted) return;
    final chat = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SourceLoginView(api: widget.api, draftId: draftId),
      ),
    );
    if (chat == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _runs(String id) async {
    final result = await widget.api.runs(id);
    if (!mounted) return;
    final rows = sourceMaps(result['items']);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Text('最近运行', style: Theme.of(context).textTheme.titleLarge),
            if (rows.isEmpty) const ListTile(title: Text('还没有运行记录')),
            for (final row in rows)
              ListTile(
                title: Text(sourceStatus(row['status'])),
                subtitle: Text(
                  '${_time(row['started_at'])}\n发现 ${row['discovered_count'] ?? 0} / 入队待评估 ${row['enqueued_count'] ?? 0}${(row['error']?.toString() ?? '').isNotEmpty ? '\n${row['error']}' : ''}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _archive(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档来源？'),
        content: const Text('停止后续发现，历史内容与来源归属会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.api.archive(id);
  }

  String _time(dynamic value) {
    if (value == null || (value is num && value <= 0)) return '等待首次发现';
    if (value is num && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
      ).toLocal().toString().split('.').first;
    }
    return value?.toString() ?? '尚未运行';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      title: const Text('自定义来源'),
      actions: [
        IconButton(
          tooltip: '刷新来源',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '在对话中提供网站或 RSS、Atom、JSON Feed 地址，说明想看的内容。试跑后由你批准启用；每个来源的份额与内置来源平级。',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('addSourceInChat'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('去聊一聊添加来源'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          for (final e in _executors.where((e) => e['id'] == 'ego'))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['available'] == true
                          ? 'Ego Lite 已就绪'
                          : 'Ego Lite：${sourceStatus(e['setup_state'] ?? e['status'])}',
                    ),
                    const Text('网页在后端通过 Ego Lite 发现；公开订阅源无需浏览器。'),
                    if (e['detail'] != null) Text(e['detail'].toString()),
                    if (e['managed'] == true &&
                        e['platform_supported'] != false &&
                        !['ready', 'preparing'].contains(e['setup_state']))
                      OutlinedButton(
                        onPressed: _busy.contains('ego')
                            ? null
                            : () => _perform('ego', () async {
                                await widget.api.prepareEgo();
                              }),
                        child: const Text('准备 Ego Lite'),
                      ),
                  ],
                ),
              ),
            ),
          if (!_loading && _items.isEmpty && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有自定义来源，先去聊一聊添加。'),
            ),
          for (final source in _items) _card(source),
        ],
      ),
    ),
  );
  Widget _card(Map<String, dynamic> source) {
    final id = source['source_id'].toString(),
        enabled = source['enabled'] == true;
    final busy = _busy.contains(id);
    final flows = sourceMaps(source['workflows']);
    final health = source['health'] is Map
        ? Map<String, dynamic>.from(source['health'])
        : <String, dynamic>{};
    return Card(
      key: ValueKey('source-$id'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source['name']?.toString() ?? '未命名来源',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(enabled ? sourceStatus(health['status']) : '已停用'),
            Text(
              source['entry_url']?.toString() ??
                  source['url']?.toString() ??
                  '',
            ),
            if (source['intent'] != null) Text(source['intent'].toString()),
            Text(
              '份额 ${source['target_share']} · 每 ${source['interval_minutes']} 分钟',
            ),
            if (health['last_success_at'] != null)
              Text('最近成功：${_time(health['last_success_at'])}'),
            if (health['next_run_at'] != null)
              Text('下次发现：${_time(health['next_run_at'])}'),
            if ((health['last_error'] ?? '').toString().isNotEmpty)
              Text(health['last_error'].toString()),
            if (flows.isNotEmpty)
              ExpansionTile(
                title: Text('${flows.length} 个发现任务'),
                children: [
                  for (final f in flows)
                    ListTile(
                      title: Text(f['intent']?.toString() ?? ''),
                      subtitle: Text(
                        '${f['executor'] == 'ego' ? '网页（Ego Lite）' : '订阅源'} · ${sourceStatus(f['status'])}',
                      ),
                    ),
                ],
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => _edit(source),
                  child: const Text('来源设置'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _perform(id, () async {
                          await widget.api.update(id, {'enabled': !enabled});
                        }),
                  child: Text(enabled ? '停用' : '启用'),
                ),
                if (flows.any((f) => f['executor'] != 'http'))
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _perform(id, () => _login(id)),
                    child: const Text('重新登录'),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : () => _perform(id, () => _runs(id)),
                  child: const Text('最近运行'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _perform(id, () => _archive(id)),
                  child: const Text('归档'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
