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
          child: _placeholder(context, Icons.movie_outlined),
        ),
      );
    }
    final client = context.read<ApiClient>();
    final token = client.sessionToken;
    // Keep native and web on the same backend-proxied image path. Direct CDN
    // requests can be rejected on mobile networks because of hotlink, DNS, or
    // TLS policy differences, while the backend proxy also provides caching.
    final imageUrl = proxyImageUrl(url, client.baseUrl, token: token);
    final headers = token.isEmpty ? null : {'Cookie': 'obc_session=$token'};
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: headers,
        width: width,
        height: height,
        fit: BoxFit.cover,
        fadeInDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        placeholder: (_, _) => _placeholder(context, Icons.image_outlined),
        errorWidget: (_, _, _) =>
            _placeholder(context, Icons.broken_image_outlined),
      ),
    );
  }

  Widget _placeholder(BuildContext context, IconData icon) {
    final palette = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surfaceMuted, palette.lavenderSoft],
        ),
      ),
      child: Center(child: Icon(icon, size: 32, color: palette.lineStrong)),
    );
  }
}
