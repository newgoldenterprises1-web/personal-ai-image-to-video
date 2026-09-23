import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_image_to_video/main.dart';

void main() {
  testWidgets('studio launches', (tester) async {
    await tester.pumpWidget(const StudioApp());
    expect(find.text('My YouTube Video'), findsOneWidget);
    expect(find.text('Add images'), findsOneWidget);
  });
}
