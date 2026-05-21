import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ad_banner_admob_stub.dart'
    if (dart.library.js_interop) 'ad_banner_admob_web.dart';

class AdBannerWidget extends StatelessWidget {
  final String adType;
  final String bannerImageUrl;
  final String bannerLinkUrl;
  final String publisherId;
  final String adUnitId;

  const AdBannerWidget({
    super.key,
    required this.adType,
    this.bannerImageUrl = '',
    this.bannerLinkUrl = '',
    this.publisherId = '',
    this.adUnitId = '',
  });

  @override
  Widget build(BuildContext context) {
    switch (adType) {
      case 'banner':
        if (bannerImageUrl.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          onTap: bannerLinkUrl.isNotEmpty
              ? () async {
                  final ok = await launchUrl(
                    Uri.parse(bannerLinkUrl),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok) {
                    debugPrint('Could not launch $bannerLinkUrl');
                  }
                }
              : null,
          child: Image.network(
            bannerImageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
      case 'admob':
        if (publisherId.isEmpty || adUnitId.isEmpty) {
          return const SizedBox.shrink();
        }
        return buildAdmobView(publisherId, adUnitId);
      default:
        return const SizedBox.shrink();
    }
  }
}
