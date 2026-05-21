import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vereinsappell/widgets/ad_banner_widget.dart';

void main() {
  group('AdBannerWidget', () {
    testWidgets('renders nothing for ad_type none', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdBannerWidget(adType: 'none'))),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('renders nothing for ad_type banner with empty image URL', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdBannerWidget(adType: 'banner', bannerImageUrl: ''),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders tappable image for ad_type banner with URL', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdBannerWidget(
              adType: 'banner',
              bannerImageUrl: 'https://example.com/sponsor.png',
              bannerLinkUrl: 'https://example.com',
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('renders nothing for ad_type admob with empty publisher ID', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdBannerWidget(adType: 'admob', publisherId: '', adUnitId: ''),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
    });
  });
}
