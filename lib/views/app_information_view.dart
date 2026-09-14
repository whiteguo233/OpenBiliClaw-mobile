import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppDocument {
  privacy('隐私政策', 'assets/legal/privacy_zh.md'),
  support('使用与支持', 'assets/legal/support_zh.md');

  const AppDocument(this.title, this.asset);

  final String title;
  final String asset;
}

/// Bundled documents stay available before login and while the backend is down.
class AppInformationView extends StatefulWidget {
  const AppInformationView({super.key, required this.document});

  final AppDocument document;

  @override
  State<AppInformationView> createState() => _AppInformationViewState();
}

class _AppInformationViewState extends State<AppInformationView> {
  late Future<String> _content = rootBundle.loadString(widget.document.asset);

  @override
  void didUpdateWidget(AppInformationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _content = rootBundle.loadString(widget.document.asset);
    }
  }

  Future<void> _openLink(String? href) async {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null || !{'https', 'mailto'}.contains(uri.scheme)) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Retain the readable document if no browser/mail application is available.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('暂时无法打开链接，请稍后重试：$uri')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.document.title)),
    body: SafeArea(
      top: false,
      child: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('文档加载失败，请重试。'),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _content = rootBundle.loadString(widget.document.asset);
                      }),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Markdown(
                data: snapshot.data!,
                selectable: true,
                padding: const EdgeInsets.all(24),
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.65),
                    ),
                onTapLink: (_, href, _) => _openLink(href),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class AppInformationLinks extends StatelessWidget {
  const AppInformationLinks({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final document in AppDocument.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ExcludeSemantics(
            child: Icon(
              document == AppDocument.privacy
                  ? Icons.privacy_tip_outlined
                  : Icons.help_outline_rounded,
            ),
          ),
          title: Text(document.title),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => AppInformationView(document: document),
            ),
          ),
        ),
    ],
  );
}
