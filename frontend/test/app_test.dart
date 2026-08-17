import 'package:flutter_test/flutter_test.dart';
import 'package:nse_paper_trading/app/theme.dart';

void main() {
  test('uses the professional dark trading theme', () {
    expect(AppTheme.dark.brightness.name, 'dark');
    expect(AppTheme.dark.scaffoldBackgroundColor.toARGB32(), 0xFF070B12);
  });
}
