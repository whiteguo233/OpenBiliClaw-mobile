import 'dart:async';

import 'package:flutter/material.dart';

import '../api/custom_sources_api.dart';
import '../api/diagnostics_api.dart';
import 'custom_sources_view.dart';

/// The same anomaly history as desktop settings; reads never trigger a retry.
class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({super.key, required this.api, this.sourceId = ''});
  final DiagnosticsApi api;
  final String sourceId;
  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _items = [];
  bool _loading = false, _active = true, _routeVisible = true;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_active && _routeVisible) unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _timer?.cancel();
    setState(() => _loading = true);
    try {
      final data = await widget.api.list(
        limit: widget.sourceId.isEmpty ? 100 : 500,
      );
      if (!mounted) return;
      setState(() {
        if (data['source_history_available'] == false) {
          _error = '来源异常记录暂时无法刷新，已显示的记录会保留。';
        } else {
          _items = sourceMaps(data['alerts'])
              .where(
                (item) =>
                    widget.sourceId.isEmpty ||
                    item['source_id'] == widget.sourceId,
              )
              .toList();
          _error = '';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = '异常记录暂时无法刷新，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_active && _routeVisible) {
          _timer = Timer(const Duration(seconds: 15), _load);
        }
      }
    }
  }

  String _time(dynamic value) => value is num && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(
          (value * 1000).round(),
        ).toLocal().toString().split('.').first
      : '';

  Future<void> _source(String id) async {
    _routeVisible = false;
    _timer?.cancel();
    final openChat = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomSourcesView(
          api: CustomSourcesApi(widget.api.client),
          initialSourceId: id,
        ),
      ),
    );
    if (!mounted) return;
    _routeVisible = true;
    if (openChat == true) {
      Navigator.pop(context, true);
      return;
    }
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.sourceId.isEmpty ? '异常记录' : '来源异常记录'),
      actions: [
        IconButton(
          tooltip: '刷新异常记录',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text('短暂采集失败先自动重试，连续 3 次失败会提醒；登录或安全验证立即提醒。恢复后仍保留记录。'),
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_items.isEmpty && !_loading && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无异常记录'),
            ),
          for (final item in _items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['severity'] == 'info'
                          ? '已恢复'
                          : item['severity'] == 'error'
                          ? '错误'
                          : '警告'} · ${item['source_name'] ?? item['source'] ?? ''}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(item['message']?.toString() ?? ''),
                    Text(_time(item['last_seen'])),
                    if ((item['count'] as num? ?? 1) > 1)
                      Text('发生 ${item['count']} 次'),
                    if (item['category'] == 'discovery' &&
                        (item['source_id']?.toString() ?? '').isNotEmpty)
                      TextButton(
                        onPressed: () => _source(item['source_id'].toString()),
                        child: const Text('查看来源'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
