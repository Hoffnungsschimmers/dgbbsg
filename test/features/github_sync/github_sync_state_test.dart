import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/core/github/github_push.dart';
import 'package:cfnb_app/features/github_sync/github_sync_state.dart';

class _FakeGithubPush extends GithubPush {
  final Object? pushError;
  final Object? pullError;
  final String? pullSha;

  _FakeGithubPush({this.pushError, this.pullError, this.pullSha})
      : super(token: 't', repo: 'o/r');

  @override
  Future<int> pushFile(String path, String content,
      {String? message, int maxRetries = 2}) async {
    if (pushError != null) throw pushError!;
    return 200;
  }

  @override
  Future<(String?, String?)> pullFile(String path) async {
    if (pullError != null) throw pullError!;
    return ('content', pullSha);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer() async {
    SharedPreferences.setMockInitialValues({});
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    final container = ProviderContainer(overrides: [
      configRepositoryProvider.overrideWith((ref) => repo),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  GithubSyncNotifier makeNotifier(
      ProviderContainer container, GithubPush Function() factory) {
    final provider = StateNotifierProvider<GithubSyncNotifier, GithubSyncState>(
        (ref) => GithubSyncNotifier(ref, githubFactory: (cfg) => factory()));
    return container.read(provider.notifier);
  }

  test('pushToGithub reports success when SHA refresh fails', () async {
    final container = await makeContainer();
    final notifier = makeNotifier(
        container, () => _FakeGithubPush(pullError: Exception('net down')));

    await notifier.pushToGithub();

    final s = notifier.state;
    expect(s.pushing, isFalse);
    expect(s.error, isNull);
    expect(s.message, contains('推送成功'));
  });

  test('pushToGithub updates sha on successful refresh', () async {
    final container = await makeContainer();
    final notifier =
        makeNotifier(container, () => _FakeGithubPush(pullSha: 'sha-new'));

    await notifier.pushToGithub();

    expect(notifier.state.error, isNull);
    expect(notifier.state.remoteSha, 'sha-new');
    expect(notifier.state.message, contains('推送成功'));
  });

  test('pushToGithub reports failure when push itself throws', () async {
    final container = await makeContainer();
    final notifier = makeNotifier(
        container, () => _FakeGithubPush(pushError: Exception('HTTP 422')));

    await notifier.pushToGithub();

    expect(notifier.state.error, contains('推送失败'));
    expect(notifier.state.message, isNull);
  });

  test('pushToGithub sets error when GitHub not configured', () async {
    final container = await makeContainer();
    final provider = StateNotifierProvider<GithubSyncNotifier, GithubSyncState>(
        (ref) => GithubSyncNotifier(ref));
    final notifier = container.read(provider.notifier);

    await notifier.pushToGithub();

    expect(notifier.state.error, contains('未配置'));
  });
}