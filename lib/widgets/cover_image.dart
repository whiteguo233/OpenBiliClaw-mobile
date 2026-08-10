import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../api/utils.dart';
import '../theme/app_theme.dart';

class CoverImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final double borderRadius;

  const CoverImage({
    super.key,
    required this.url,
    this.width = double.infinity,
    this.height = 140,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: _placeholder(Icons.movie_outlined),
        ),
      );
    }
    final client = context.read<ApiClient>();
    final token = client.sessionToken;
    // ponytail: 原生平台 B 站封面直连图床（省掉海外服务器代理两跳）；web 端 CORS 受限走代理，
    // 其他平台图床可能有防盗链/签名时效也走代理（服务器有磁盘缓存）
    final viaProxy = kIsWeb || !url.contains('hdslb.com');
    final imageUrl = viaProxy
        ? proxyImageUrl(url, client.baseUrl, token: token)
        : url;
    final headers = !viaProxy || token.isEmpty
        ? null
        : {'Cookie': 'obc_session=$token'};
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: headers,
        width: width,
        height: height,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (_, _) => _placeholder(Icons.image_outlined),
        errorWidget: (_, _, _) => _placeholder(Icons.broken_image_outlined),
      ),
    );
  }

  Widget _placeholder(IconData icon) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceMuted, AppColors.lavenderSoft],
        ),
      ),
      child: Center(child: Icon(icon, size: 32, color: AppColors.lineStrong)),
    );
  }
}
