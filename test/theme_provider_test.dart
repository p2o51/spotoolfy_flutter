import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/providers/theme_provider.dart';

void main() {
  test('ThemeProvider initializes with a color scheme', () {
    final provider = ThemeProvider();
    expect(provider.colorScheme, isNotNull);
  });

  testWidgets('ThemeProvider updates when system brightness changes', (tester) async {
    final themeProvider = ThemeProvider();

    Future<void> pumpWithBrightness(Brightness brightness) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: themeProvider,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(platformBrightness: brightness),
              child: Builder(
                builder: (context) {
                  final scheme = context.watch<ThemeProvider>().colorScheme;
                  return ElevatedButton(
                    onPressed: () => context.read<ThemeProvider>().updateThemeFromSystem(context),
                    child: Text(scheme.brightness == Brightness.dark ? 'dark' : 'light'),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    await pumpWithBrightness(Brightness.light);
    expect(find.text('light'), findsOneWidget);

    await pumpWithBrightness(Brightness.dark);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('dark'), findsOneWidget);
  });
}
