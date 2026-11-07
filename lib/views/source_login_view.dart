import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/custom_sources_api.dart';

/// Operates the backend's Ego tab through its authenticated screenshot/action API.
/// The website session remains on the backend; no credentials enter chat.
class SourceLoginView extends StatefulWidget {
  const SourceLoginView({super.key, required this.api, required this.draftId});
  final CustomSourcesApi api;
  final String draftId;
  @override
  State<SourceLoginView> createState() => _SourceLoginViewState();
}

class _SourceLoginViewState extends State<SourceLoginView>
    with WidgetsBindingObserver {
  Uint8List? _image;
  int _imageWidth = 1, _imageHeight = 1;
  List<Map<String, dynamic>> _fields = [];
  final Set<String> _origins = {};
  String? _selector;
  final _value = TextEditingController();
  String _status = '正在打开 Ego 登录窗口…';
  bool _busy = false, _open = false, _success = false, _foreground = true;
  Timer? _timer;
  bool _polling = false;
  int _imageEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_operate(_openSession));
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_open && !_busy && !_polling && !_success && _foreground) {
        unawaited(_pollScreenshot());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _value.dispose();
    // Best effort on exit; backend expiry covers force termination/offline exit.
    unawaited(widget.api.closeLogin(widget.draftId).catchError((Object _) {}));
    super.dispose();
  }

  void _snapshot(Map<String, dynamic> data) {
    final seen = <String>{};
    _fields = sourceMaps(data['elements'])
        .map(
          (e) => {
            ...e,
            'selector': (e['path_selector']?.toString().isNotEmpty ?? false)
                ? e['path_selector']
                : e['selector'],
          },
        )
        .where(
          (e) =>
              e['tag']?.toString().toLowerCase() == 'input' &&
              (e['selector']?.toString() ?? '').isNotEmpty &&
              seen.add(e['selector'].toString()) &&
              !['hidden', 'submit', 'button'].contains(e['type']),
        )
        .toList();
    if (!_fields.any((f) => f['selector'] == _selector)) {
      _selector = _fields.firstOrNull?['selector']?.toString();
    }
    final origins =
        data['suggested_login_origins'] ?? data['blocked_navigation_origins'];
    if (origins is List) {
      _origins
        ..clear()
        ..addAll(origins.whereType<String>());
    }
  }

  // A passive screenshot must never swallow the user's next action.
  Future<void> _pollScreenshot() async {
    _polling = true;
    final epoch = _imageEpoch;
    try {
      await _refresh();
    } catch (error) {
      if (mounted && epoch == _imageEpoch && !_busy) {
        _open = false;
        _status = '画面连接中断：$error。可重新打开登录窗口。';
      }
    } finally {
      _polling = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _operate(Future<void> Function() operation) async {
    if (_busy || !mounted) return;
    _imageEpoch += 1;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (!mounted) return;
      _open =
          false; // Stop polling; expose explicit reopening after failure/expiry.
      _status = '操作未完成：$error。可重新打开登录窗口。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSession([String origin = '']) async {
    final draft = await widget.api.draft(widget.draftId);
    if (!mounted) return;
    final suggested = draft['suggested_login_origins'];
    if (suggested is List) _origins.addAll(suggested.whereType<String>());
    final data = await widget.api.takeover(widget.draftId, origin: origin);
    if (!mounted) {
      // Exit may reach the server before an in-flight takeover request.
      await widget.api.closeLogin(widget.draftId);
      return;
    }
    _snapshot(data);
    _open = true;
    _success = false;
    _status = '在下方网站画面完成登录或验证，再继续试跑。';
    await _refresh();
  }

  Future<void> _refresh() async {
    final epoch = _imageEpoch;
    final bytes = await widget.api.screenshot(widget.draftId);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      if (mounted && epoch == _imageEpoch) {
        _image = bytes;
        _imageWidth = frame.image.width;
        _imageHeight = frame.image.height;
      }
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  Future<void> _act(Map<String, dynamic> action) async {
    final result = await widget.api.action(widget.draftId, action);
    if (!mounted) return;
    _snapshot(result);
    await _refresh();
  }

  Future<void> _resume() async {
    setState(() {
      _open = false;
      _status = '正在实际试跑，请稍候…';
    });
    final result = await widget.api.resume(widget.draftId);
    if (!mounted) return;
    _success = result['status'] == 'ready';
    _status = _success
        ? '试跑成功。返回对话后继续确认；新建或修改流程仍需批准。'
        : (result['detail']?.toString() ?? '仍需完成网站验证，请重新打开登录窗口。');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      title: const Text('来源登录'),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, true),
          child: const Text('返回对话'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('登录状态保存在运行 OpenBiliClaw 的设备上。请在网站画面操作，勿将密码发到聊天。'),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(_status, key: const Key('sourceLoginStatus')),
        ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!_open && !_success)
              OutlinedButton(
                onPressed: _busy ? null : () => _operate(_openSession),
                child: const Text('重新打开登录窗口'),
              ),
            if (_open)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _operate(() async {
                        _snapshot(await widget.api.takeover(widget.draftId));
                        await _refresh();
                      }),
                child: const Text('刷新画面'),
              ),
            for (final key in ['Tab', 'Enter'])
              OutlinedButton(
                onPressed: _busy || !_open
                    ? null
                    : () => _operate(() => _act({'action': 'key', 'key': key})),
                child: Text(key == 'Tab' ? '下一个输入框' : '回车'),
              ),
            FilledButton(
              key: const Key('sourceLoginResume'),
              onPressed: _busy || !_open ? null : () => _operate(_resume),
              child: const Text('登录完成，继续试跑'),
            ),
          ],
        ),
        for (final origin in _origins)
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _operate(() => _openSession(origin)),
            child: Text('允许此登录或验证页面：$origin'),
          ),
        const SizedBox(height: 12),
        if (_image != null)
          LayoutBuilder(
            builder: (context, constraints) => Semantics(
              label: '网站登录画面，点击可操作',
              child: GestureDetector(
                onTapUp: _busy || !_open
                    ? null
                    : (details) {
                        final width = constraints.maxWidth;
                        final height = width * _imageHeight / _imageWidth;
                        unawaited(
                          _operate(
                            () => _act({
                              'action': 'click',
                              'x':
                                  (details.localPosition.dx /
                                          width *
                                          _imageWidth)
                                      .clamp(0, _imageWidth - 1)
                                      .toDouble(),
                              'y':
                                  (details.localPosition.dy /
                                          height *
                                          _imageHeight)
                                      .clamp(0, _imageHeight - 1)
                                      .toDouble(),
                            }),
                          ),
                        );
                      },
                child: Image.memory(
                  _image!,
                  key: const Key('sourceLoginScreenshot'),
                  height: constraints.maxWidth * _imageHeight / _imageWidth,
                  width: constraints.maxWidth,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (_fields.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _selector,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '选择网站输入框'),
            items: _fields
                .map(
                  (f) => DropdownMenuItem(
                    value: f['selector'].toString(),
                    child: Text(
                      f['type'] == 'password'
                          ? '密码输入框'
                          : '${f['type'] == 'email'
                                ? '邮箱'
                                : f['type'] == 'tel'
                                ? '电话'
                                : '文字'}输入框 ${_fields.indexOf(f) + 1}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _selector = value),
          ),
        TextField(
          controller: _value,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '输入内容（仅发送给网站）'),
        ),
        OutlinedButton(
          onPressed: _busy || !_open || _selector == null
              ? null
              : () {
                  final text = _value.text;
                  _value.clear();
                  unawaited(
                    _operate(
                      () => _act({
                        'action': 'fill',
                        'selector': _selector,
                        'value': text,
                      }),
                    ),
                  );
                },
          child: const Text('填入网站'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('sourceLoginReturn'),
          onPressed: _busy ? null : () => Navigator.pop(context, true),
          child: const Text('返回对话'),
        ),
      ],
    ),
  );
}
