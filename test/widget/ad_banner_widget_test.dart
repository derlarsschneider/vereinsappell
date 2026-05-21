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

    testWidgets('renders admob view for ad_type admob with both IDs set', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdBannerWidget(
              adType: 'admob',
              publisherId: 'ca-pub-1234567890123456',
              adUnitId: '9876543210',
            ),
          ),
        ),
      );
      // On non-web (test environment), buildAdmobView returns SizedBox.shrink.
      // The key assertion is that the widget builds without error and no Image is shown.
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
