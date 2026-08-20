import 'package:cfnb_app/core/github/github_push.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GithubPush.buildPutBody', () {
    test('includes sha when updating', () {
      final body = GithubPush.buildPutBody(
        path: 'ip.txt', content: 'x', branch: 'main', sha: 'ABC',
      );
      expect(body['sha'], 'ABC');
      expect(body['branch'], 'main');
      expect(body['content'], isNotEmpty);
    });
    test('omits sha for new file', () {
      final body = GithubPush.buildPutBody(
        path: 'ip.txt', content: 'x', branch: 'main',
      );
      expect(body.containsKey('sha'), isFalse);
    });
  });

  group('GithubPush.pushFile', () {
    test('creates new file when GET 404', () async {
      Future<Response<dynamic>> fakeSender(RequestOptions o) async {
        if (o.method == 'GET') {
          throw DioException(requestOptions: o, response: Response<dynamic>(statusCode: 404, requestOptions: o));
        }
        // PUT
        expect(o.method, 'PUT');
        final data = o.data as Map<String, dynamic>;
        expect(data.containsKey('sha'), isFalse);
        return Response<dynamic>(statusCode: 201, requestOptions: o, data: <String, dynamic>{});
      }
      final gh = GithubPush(token: 't', repo: 'o/cf-ip', sender: fakeSender);
      final code = await gh.pushFile('ip.txt', 'hello');
      expect(code, 201);
    });

    test('updates existing file when GET 200', () async {
      Future<Response<dynamic>> fakeSender(RequestOptions o) async {
        if (o.method == 'GET') {
          return Response<dynamic>(statusCode: 200, requestOptions: o, data: <String, dynamic>{'sha': 'SHA1'});
        }
        final data = o.data as Map<String, dynamic>;
        expect(data['sha'], 'SHA1');
        return Response<dynamic>(statusCode: 200, requestOptions: o, data: <String, dynamic>{});
      }
      final gh = GithubPush(token: 't', repo: 'o/cf-ip', sender: fakeSender);
      final code = await gh.pushFile('ip.txt', 'hello');
      expect(code, 200);
    });
  });

  group('isPushable', () {
    test('only .top files', () {
      expect(GithubPush.isPushable('addressesapi_top.txt'), isTrue);
      expect(GithubPush.isPushable('addressesapi.txt'), isFalse);
      expect(GithubPush.isPushable('ip.txt'), isFalse);
    });
  });
}
