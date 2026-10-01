import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konta_gestor/shared/widgets/custom_text_field.dart';

void main() {
  group('CustomTextField Widget Tests', () {
    testWidgets('CustomTextField renders correctly with label', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomTextField(
              label: 'Test Label',
              controller: controller,
            ),
          ),
        ),
      );

      // Verificamos que el label exista
      expect(find.text('Test Label'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('CustomTextField validation returns error on empty', (WidgetTester tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: CustomTextField(
                label: 'Test Label',
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Trigger validation
      formKey.currentState!.validate();
      await tester.pump();

      // Expect to see the validation error message
      expect(find.text('Este campo es obligatorio'), findsOneWidget);
    });

    testWidgets('CustomTextField readOnly does not show error on empty', (WidgetTester tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: CustomTextField(
                label: 'Test Label',
                controller: controller,
                readOnly: true,
              ),
            ),
          ),
        ),
      );

      // Trigger validation
      formKey.currentState!.validate();
      await tester.pump();

      // Expect NOT to see the validation error message
      expect(find.text('Este campo es obligatorio'), findsNothing);
    });

  });
}
