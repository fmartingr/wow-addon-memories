import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/platform/discovery.dart';
import 'package:wow_journey/src/platform/folder_picker.dart';
import 'package:wow_journey/src/ui/folder_flow.dart';

import 'support/fakes.dart';

class _BrokenPicker implements FolderPicker {
  @override
  Future<String?> pickFolder({String? initialDirectory, String? confirmText}) =>
      Future.error(StateError('no portal'));
}

class _BrokenDiscovery implements Discovery {
  @override
  Future<List<WowFolder>> discover() async => const [];

  @override
  Future<FlavorCheck> validate(String path) =>
      Future.error(StateError('isolate lost'));
}

void main() {
  group('pickWowFolder', () {
    test('a picker that fails says the picker could not open', () async {
      final pick = await pickWowFolder(_BrokenPicker(), FakeDiscovery());
      expect(pick, isA<WowPickRefused>());
      expect((pick as WowPickRefused).message, pickerFailedText);
    });

    test('a check that fails says the folder could not be checked', () async {
      final pick = await pickWowFolder(
        FakeFolderPicker([retailDir]),
        _BrokenDiscovery(),
      );
      expect(pick, isA<WowPickRefused>());
      expect((pick as WowPickRefused).message, checkFailedText);
    });
  });
}
