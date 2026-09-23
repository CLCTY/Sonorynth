import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/netease_local_api.dart';

void main() {
  group('NeteaseCrypto', () {
    test('weapi produces a valid encrypted form', () {
      final encrypted = NeteaseCrypto.weapi({'s': '测试', 'limit': 30});

      expect(encrypted['params'], isNotEmpty);
      expect(encrypted['encSecKey'], hasLength(256));
      expect(encrypted['encSecKey'], matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('eapi output is deterministic uppercase block data', () {
      final first = NeteaseCrypto.eapi('/api/song/detail', {
        'c': '[{"id":347230}]',
      });
      final second = NeteaseCrypto.eapi('/api/song/detail', {
        'c': '[{"id":347230}]',
      });

      expect(first, second);
      expect(first['params'], matches(RegExp(r'^[0-9A-F]+$')));
      expect(first['params']!.length % 32, 0);
    });
  });
}
