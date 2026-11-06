import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepfake_software/theme/app_theme.dart';
import 'package:deepfake_software/widgets/shared_widgets.dart';

void main() {
  testWidgets('primary action remains readable on a narrow layout',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var invoked = false;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
              child: SizedBox(
                  width: 180,
                  child: PrimaryButton(
                    label: 'Enter your live studio',
                    icon: Icons.arrow_outward_rounded,
                    onPressed: () => invoked = true,
                  ))),
        )));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Enter your live studio'));
    expect(invoked, isTrue);
  });
}
