import 'package:localsend_app/provider/network/webrtc/signaling_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../../../mocks.mocks.dart';

void main() {
  group('SignalingService', () {
    test('does not connect to public signaling servers by default', () {
      final persistence = MockPersistenceService();
      when(persistence.getSignalingServers()).thenReturn(null);
      when(persistence.getStunServers()).thenReturn(null);

      final service = ReduxNotifier.test(
        redux: SignalingService(persistence: persistence),
      );

      expect(service.state.signalingServers, isEmpty);
      expect(service.state.stunServers, isEmpty);
    });

    test('keeps explicitly configured signaling servers', () {
      final persistence = MockPersistenceService();
      when(persistence.getSignalingServers()).thenReturn(['wss://example.test/ws']);
      when(persistence.getStunServers()).thenReturn(['stun:example.test:3478']);

      final service = ReduxNotifier.test(
        redux: SignalingService(persistence: persistence),
      );

      expect(service.state.signalingServers, ['wss://example.test/ws']);
      expect(service.state.stunServers, ['stun:example.test:3478']);
    });
  });
}
