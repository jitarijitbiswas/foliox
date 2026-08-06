import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nse_paper_trading/app/app.dart';

void main() {
  testWidgets('renders the authentication gate', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PaperTradingApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Foliox'), findsOneWidget);
    expect(
      find.text('Google authentication setup is pending.'),
      findsOneWidget,
    );
  });
}
