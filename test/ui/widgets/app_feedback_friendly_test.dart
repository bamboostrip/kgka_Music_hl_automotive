import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/widgets/app_feedback.dart';

void main() {
  group('friendlyServiceErrorMessage', () {
    test('hides upstream URL leak behind network hint', () {
      const raw =
          'ApiException(500): Upstream API error: HTTP 发送失败: error sending request for url (https://gateway.kugou.com/v1/rcmd_list?ap···';
      final message = friendlyServiceErrorMessage(raw);
      expect(message, '网络连接失败，请检查网络设置后重试');
      expect(message, isNot(contains('gateway')));
      expect(message, isNot(contains('ApiException')));
      expect(message, isNot(contains('https://')));
    });

    test('maps timeout to timeout hint', () {
      expect(
        friendlyServiceErrorMessage('ApiException(408): 请求超时，请检查网络后重试'),
        '请求超时，请检查网络后重试',
      );
    });

    test('maps socket/DNS failure to network hint', () {
      expect(
        friendlyServiceErrorMessage('SocketException: Failed host lookup'),
        '网络连接失败，请检查网络设置后重试',
      );
    });

    test('generic error does not leak raw text', () {
      final message = friendlyServiceErrorMessage('ApiException(400): 参数错误');
      expect(message, '服务暂时不可用，请稍后重试');
      expect(message, isNot(contains('参数错误')));
    });
  });
}
