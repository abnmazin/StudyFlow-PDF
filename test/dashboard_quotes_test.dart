import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/dashboard_quote.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_palette.dart';
import 'package:studyflow_pdf/widgets/dashboard/dashboard_quotes_card.dart';

/// What this file exists to prevent.
///
/// Two failure modes, neither of which a reviewer can see by reading the widget:
///
/// 1. The panel has a fixed height, so a quotation one line longer than the one
///    the admin tested with either overflows it or shoves the author off the
///    bottom. The text shrinks against the palette's own floor, so the assertion
///    is that a quotation at the maximum the Firestore rule allows still fits and
///    still prints its author.
/// 2. The rotation timer is the classic Flutter leak: a `Timer.periodic` that
///    outlives its `State` calls `setState` after disposal. Disposing the panel
///    while a rotation is armed is what the dashboard does every time the reader
///    opens a PDF, so it is exactly the case worth testing.
///
/// Fixtures at the top, so the bodies read as behaviour rather than as data.
class QuoteFixture {
  const QuoteFixture._();

  /// A real quotation, short enough to sit on one line.
  static final short = DashboardQuote(
    id: 'q1',
    text: 'على قدر أهل العزم تأتي العزائم',
    author: 'المتنبي',
  );

  /// Two sentences: the middle case, where the text wraps but fits.
  static final medium = DashboardQuote(
    id: 'q2',
    text: 'العلم في الصغر كالنقش على الحجر لا يمحوه Winds بعد سنين، '
        'والعقل إذا حضر مع مسافر لم يتركه في الطريق.',
    author: 'الإمام الشافعي',
  );

  /// The maximum the Firestore rule allows, and the one that would overflow a
  /// card sized for a two-line sentence. This is the fixture that has to shrink.
  static final maximum = DashboardQuote(
    id: 'q3',
    text: List.filled(
      DashboardQuote.maxTextLength ~/ 12,
      'ومن سار على الدرب وصل',
    ).join('، '),
    author: 'حكمة طويلة',
  );

  static final pinned = DashboardQuote(
    id: 'q4',
    text: 'اطلبوا العلم من المهد إلى اللحد',
    author: 'الإمام الشافعي',
    pinned: true,
  );
}

/// The panel alone, in the RTL and dark surface it is drawn in, with no provider
/// and no Firebase behind it — the same reason `DashboardReadingStats.days`
/// exists.
Future<void> pumpPanel(
  WidgetTester tester, {
  required List<DashboardQuote> quotes,
  double width = 900,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: DashboardQuotesCard(quotes: quotes),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a quotation and its author both fit inside the fixed height', (
    tester,
  ) async {
    await pumpPanel(tester, quotes: [QuoteFixture.short]);

    expect(tester.takeException(), isNull, reason: 'the panel must not overflow');

    // Asserted against the render tree, not against widget properties: a `Text`
    // carrying the right string says nothing about whether it is on the card.
    final panelBottom = tester.getRect(find.byType(DashboardQuotesCard)).bottom;
    final authorBottom = tester
        .getRect(find.byKey(const ValueKey('quote-author')))
        .bottom;
    expect(
      authorBottom,
      lessThanOrEqualTo(panelBottom),
      reason: 'the author must stay on the card, not below it',
    );
  });

  testWidgets('the longest allowed quotation shrinks instead of overflowing', (
    tester,
  ) async {
    // Narrow as well as long: this is the width the panel gets inside the
    // section, and a quotation at the Firestore ceiling is the input that has to
    // survive it.
    await pumpPanel(tester, quotes: [QuoteFixture.maximum], width: 600);
    expect(tester.takeException(), isNull);

    // It shrinks, but only down to the floor the palette names. Below this the
    // sentence stops reading as a quotation, and an overflow is worse than a
    // small one.
    final rendered = tester
        .widget<Text>(find.byKey(const ValueKey('quote-text')))
        .style!
        .fontSize!;
    expect(
      rendered,
      inInclusiveRange(kQuoteMinFontSize, kQuoteFontSize),
      reason: 'a long quotation must scale down, but not past the floor',
    );
    expect(rendered, lessThan(kQuoteFontSize));

    // And the author is still there under it.
    expect(find.byKey(const ValueKey('quote-author')), findsOneWidget);
  });

  testWidgets('the rotation turns the page, and a pinned quotation never does', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      quotes: [QuoteFixture.short, QuoteFixture.maximum],
    );
    expect(find.text(QuoteFixture.short.text), findsOneWidget);

    // `pump` rather than `pumpAndSettle`: the panel arms a timer, and
    // `pumpAndSettle` waits for the tree to stop having scheduled frames — with
    // a rotation pending that wait times out on a test that has not failed.
    await tester.pump(kQuoteHold + kQuoteFadeDuration);
    expect(
      find.text(QuoteFixture.short.text),
      findsNothing,
      reason: 'the next quotation takes the place after the hold',
    );
    expect(find.text(QuoteFixture.maximum.text), findsOneWidget);

    // Now pin one and prove the rotation is off. This is the admin's override,
    // and it is the one behaviour of the panel that is a promise to a reader
    // rather than a decoration.
    await pumpPanel(tester, quotes: [QuoteFixture.pinned]);
    await tester.pump(kQuoteHold * 2);

    expect(find.text(QuoteFixture.pinned.text), findsOneWidget);
    expect(find.text('مثبّتة من الإدارة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty list says so instead of inventing a quotation', (
    tester,
  ) async {
    await pumpPanel(tester, quotes: const []);

    expect(find.text('لا توجد اقتباسات بعد'), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-text')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a quotation without an author is refused, at the model', () {
    // This is the rule the Firestore rule mirrors, so it is asserted where it is
    // written: an unattributed sentence on a study dashboard reads as the app's
    // own claim, and nothing else would notice.
    expect(
      DashboardQuote.validationMessage(text: 'حكمة', author: '   '),
      'اكتب اسم المؤلف أو الحكم',
    );
    expect(
      DashboardQuote.validationMessage(text: '', author: 'المتنبي'),
      'اكتب نص الاقتباس',
    );
    expect(
      DashboardQuote.validationMessage(text: 'حكمة', author: 'المتنبي'),
      isNull,
    );

    // And the ceiling is the same number the rule enforces, so an admin cannot
    // type a quotation that Firestore will then refuse.
    final tooLong = 'ا' * (DashboardQuote.maxTextLength + 1);
    expect(
      DashboardQuote.validationMessage(text: tooLong, author: 'المتنبي'),
      contains('${DashboardQuote.maxTextLength}'),
    );
  });
}
