import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/recommend_provider.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/delight_banner.dart';

class RecommendView extends StatelessWidget {
  const RecommendView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecommendProvider>(builder: (context, rp, _) {
      final delightsCount = rp.delights.length;
      return RefreshIndicator(onRefresh: () => rp.load(),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(children: [
              Container(width: 24, height: 24, decoration: BoxDecoration(
                color: const Color(0xFFFB7299), borderRadius: BorderRadius.circular(6)),
                child: const Center(child: Text('B', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))),
              const SizedBox(width: 6),
              Text('为你推荐', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600])),
              const Spacer(),
              Icon(Icons.circle, size: 6, color: rp.online ? const Color(0xFF30B980) : Colors.grey[400]),
              const SizedBox(width: 4),
              Text(rp.online ? '在线' : '离线', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ]))),
          if (!rp.online && !rp.loading)
            SliverToBoxAdapter(child: Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [Icon(Icons.wifi_off, size: 16, color: Colors.orange), SizedBox(width: 8),
                Text('无法连接后端', style: TextStyle(fontSize: 13, color: Colors.orange))]))),
          if (delightsCount > 0) ...[
            SliverToBoxAdapter(child: DelightBanner(
              delight: rp.delights[rp.delightIndex.clamp(0, delightsCount - 1)],
              currentIndex: rp.delightIndex, totalCount: delightsCount,
              onPrev: () => rp.prevDelight(),
              onNext: () => rp.nextDelight(),
              onView: () {
                final d = rp.delights[rp.delightIndex.clamp(0, delightsCount - 1)];
                _openUrl(context, d.contentUrl.isNotEmpty ? d.contentUrl : 'https://www.bilibili.com/video/${d.bvid}');
              },
              onLike: () {
                final d = rp.delights[rp.delightIndex.clamp(0, delightsCount - 1)];
                rp.respondToDelight(d.bvid, 'like');
              },
              onDislike: () {
                final d = rp.delights[rp.delightIndex.clamp(0, delightsCount - 1)];
                rp.respondToDelight(d.bvid, 'dislike');
              },
              onDismiss: () {
                final d = rp.delights[rp.delightIndex.clamp(0, delightsCount - 1)];
                rp.respondToDelight(d.bvid, 'dismiss');
              },
            )),
          ],
          if (rp.loading && rp.recommendations.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (rp.recommendations.isEmpty)
            SliverFillRemaining(child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('还没有推荐，下拉刷新试试', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
              ]),
            ))
          else
            SliverList(delegate: SliverChildListDelegate(
              rp.recommendations.map((rec) => RecommendationCard(
                rec: rec,
                onTap: () {
                  rp.reportClick(rec);
                  final url = rp.contentUrlFor(rec);
                  if (url != null) _openUrl(context, url);
                },
                onLike: () => rp.submitFeedback(rec, 'like'),
                onDislike: () => rp.submitFeedback(rec, 'dislike'),
              )).toList(),
            )),
          if (rp.recommendations.isNotEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16),
              child: Center(child: TextButton(onPressed: () => rp.append(), child: Text(rp.loading ? '加载中…' : '加载更多推荐', style: const TextStyle(color: Color(0xFFFB7299))))))),
        ]));
    });
  }

  void _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // Try B站 app scheme first; fall back to browser.
    final bvid = _extractBvid(url);
    if (bvid != null) {
      final appUri = Uri.tryParse('bilibili://video/$bvid');
      if (appUri != null) {
        try {
          if (await canLaunchUrl(appUri)) {
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (_) {}
      }
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String? _extractBvid(String url) {
    final match = RegExp(r'(BV[a-zA-Z0-9]+)').firstMatch(url);
    return match?.group(1);
  }
}
