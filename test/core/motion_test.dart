import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/widgets/motion.dart';

double _opacity(WidgetTester tester, String text) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  testWidgets('EntranceScope animates first-frame items only', (tester) async {
    final show = ValueNotifier(false);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EntranceScope(
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, late, _) => Column(
              children: [
                const FadeSlideIn(child: Text('first')),
                if (late) const FadeSlideIn(child: Text('later')),
              ],
            ),
          ),
        ),
      ),
    );
    // Initial item starts its entrance.
    expect(_opacity(tester, 'first'), lessThan(1));

    // An item built afterwards (e.g. scrolled into view) shows at once.
    show.value = true;
    await tester.pump();
    expect(_opacity(tester, 'later'), 1);

    await tester.pumpAndSettle();
    expect(_opacity(tester, 'first'), 1);
  });
}
