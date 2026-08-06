import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../api/utils.dart';

class CoverImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final double borderRadius;

  const CoverImage({super.key, required this.url, this.width = double.infinity, this.height = 140, this.borderRadius = 12});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(width: width, height: height, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(borderRadius)),
        child: const Icon(Icons.movie_outlined, color: Colors.grey, size: 40));
    }
    final client = context.read<ApiClient>();
    final token = client.sessionToken;
    final proxyUrl = proxyImageUrl(url, client.baseUrl, token: token);
    final headers = token.isNotEmpty ? {'Cookie': 'obc_session=$token'} : null;
    return ClipRRect(borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageProvider: CachedNetworkImageProvider(proxyUrl, headers: headers),
        width: width, height: height, fit: BoxFit.cover,
        placeholder: (_, _) => Container(color: Colors.grey[200]),
        errorWidget: (_, _, _) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey))));
  }
}
