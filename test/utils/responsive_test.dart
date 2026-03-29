import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotoolfy_flutter/utils/responsive.dart';

void main() {
  Future<void> pumpResponsiveHarness(
    WidgetTester tester, {
    required double width,
    required Widget child,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 1200)),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('shell layout switches to two pane at tablet breakpoint',
      (tester) async {
    Future<bool> prefersTwoPane(double width) async {
      await pumpResponsiveHarness(
        tester,
        width: width,
        child: Builder(
          builder: (context) => Text(
            context.layoutType(ResponsivePageType.shell).preferTwoPane
                ? 'two-pane'
                : 'single-pane',
          ),
        ),
      );
      return find.text('two-pane').evaluate().isNotEmpty;
    }

    expect(await prefersTwoPane(390), isFalse);
    expect(await prefersTwoPane(600), isTrue);
    expect(await prefersTwoPane(900), isTrue);
    expect(await prefersTwoPane(1280), isTrue);
  });

  testWidgets('adaptiveColumns stays consistent across standard breakpoints',
      (tester) async {
    Future<int> columnsFor(double width) async {
      await pumpResponsiveHarness(
        tester,
        width: width,
        child: Builder(
          builder: (context) => Text(
            '${context.adaptiveColumns(minTileWidth: context.layoutType(ResponsivePageType.browse).defaultMinTileWidth, min: 3, max: 6)}',
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text).first);
      return int.parse(textWidget.data!);
    }

    expect(await columnsFor(390), 3);
    expect(await columnsFor(600), 3);
    expect(await columnsFor(900), 4);
    expect(await columnsFor(1280), 6);
  });

  testWidgets('ResponsivePageContainer caps detail width on large screens',
      (tester) async {
    const contentKey = Key('detail-content');

    await pumpResponsiveHarness(
      tester,
      width: 1280,
      child: const ResponsivePageContainer(
        pageType: ResponsivePageType.detail,
        child: SizedBox(
          key: contentKey,
          width: double.infinity,
          height: 80,
        ),
      ),
    );

    final size = tester.getSize(find.byKey(contentKey));
    expect(size.width, 1080);
  });

  testWidgets('adaptive modal uses bottom sheet on mobile', (tester) async {
    await pumpResponsiveHarness(
      tester,
      width: 390,
      child: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () {
              ResponsiveNavigation.showAdaptiveModalPage<void>(
                context: context,
                showCloseButton: false,
                child: const SizedBox(
                  height: 120,
                  child: Center(child: Text('modal-child')),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheetSize = tester.getSize(find.byType(BottomSheet));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('modal-child'), findsOneWidget);
    expect(sheetSize.height, lessThan(280));
  });

  testWidgets('adaptive modal can opt into fill-height on mobile',
      (tester) async {
    await pumpResponsiveHarness(
      tester,
      width: 390,
      child: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () {
              ResponsiveNavigation.showAdaptiveModalPage<void>(
                context: context,
                showCloseButton: false,
                contentLayout: AdaptiveModalContentLayout.fillHeight,
                child: const SizedBox(
                  height: 120,
                  child: Center(child: Text('full-height-modal')),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheetSize = tester.getSize(find.byType(BottomSheet));
    expect(find.text('full-height-modal'), findsOneWidget);
    expect(sheetSize.height, greaterThan(700));
  });

  testWidgets('adaptive modal uses dialog on large screens', (tester) async {
    await pumpResponsiveHarness(
      tester,
      width: 1280,
      child: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () {
              ResponsiveNavigation.showAdaptiveModalPage<void>(
                context: context,
                showCloseButton: false,
                child: const SizedBox(
                  height: 120,
                  child: Center(child: Text('modal-child')),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('modal-child'), findsOneWidget);
  });
}
