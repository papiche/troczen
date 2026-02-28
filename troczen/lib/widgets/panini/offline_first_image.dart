import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OfflineFirstImage extends StatelessWidget {
  final String? base64Data;
  final String? networkUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;

  const OfflineFirstImage({
    super.key,
    this.base64Data,
    this.networkUrl,
    this.width,
    this.height,
    this.fit,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Priorité absolue au Base64 (100% Offline, chargement instantané)
    if (base64Data != null && base64Data!.startsWith('data:image')) {
      final base64String = base64Data!.split(',').last;
      return Image.memory(
        base64Decode(base64String),
        width: width,
        height: height,
        fit: fit ?? BoxFit.cover,
      );
    }

    // 2. Fallback sur le réseau (cached_network_image gère le RAM/Disk cache tout seul)
    if (networkUrl != null && networkUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: networkUrl!,
        width: width,
        height: height,
        fit: fit ?? BoxFit.cover,
        placeholder: (context, url) => SizedBox(
          width: width,
          height: height,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.store),
        ),
      );
    }

    // 3. Rien du tout
    return SizedBox(
      width: width,
      height: height,
      child: const Icon(Icons.store),
    );
  }
}
