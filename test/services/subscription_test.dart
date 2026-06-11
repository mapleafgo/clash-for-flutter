import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/services/subscription.dart';

void main() {
  group('isBase64Content', () {
    test('returns true for valid base64 with protocol URIs', () {
      final encoded = base64.encode(utf8.encode('ss://abc@host:443\n'));
      expect(isBase64Content(encoded), isTrue);
    });

    test('returns false for empty string', () {
      expect(isBase64Content(''), isFalse);
    });

    test('returns false for whitespace-only string', () {
      expect(isBase64Content('   '), isFalse);
    });

    test('returns false for invalid base64', () {
      expect(isBase64Content('not-base64!!!'), isFalse);
    });

    test('returns false for base64 without protocol URIs', () {
      final encoded = base64.encode(utf8.encode('just some text'));
      expect(isBase64Content(encoded), isFalse);
    });
  });

  group('parseProxyUri', () {
    test('returns null for string without ://', () {
      expect(parseProxyUri('not-a-uri'), isNull);
    });

    test('parses ss:// shadowsocks URI with base64 body', () {
      final ssBody = base64.encode(utf8.encode('aes-128-gcm:pass@host.com:8080'));
      final result = parseProxyUri('ss://$ssBody#test');
      expect(result, isNotNull);
      expect(result!['type'], 'ss');
      expect(result['name'], 'test');
      expect(result['server'], 'host.com');
      expect(result['port'], 8080);
    });

    test('parses vmess:// URI', () {
      final vmessJson = jsonEncode({
        'add': 'example.com',
        'port': '443',
        'id': 'uuid-123',
        'aid': 0,
        'scy': 'aes-128-gcm',
      });
      final encoded = base64.encode(utf8.encode(vmessJson));
      final result = parseProxyUri('vmess://$encoded#vmtest');
      expect(result, isNotNull);
      expect(result!['type'], 'vmess');
      expect(result['server'], 'example.com');
      expect(result['port'], '443');
      expect(result['uuid'], 'uuid-123');
    });

    test('parses vless:// URI', () {
      final result = parseProxyUri(
        'vless://uuid@example.com:443?security=tls#vltest',
      );
      expect(result, isNotNull);
      expect(result!['type'], 'vless');
      expect(result['server'], 'example.com');
      expect(result['port'], 443);
      expect(result['uuid'], 'uuid');
      expect(result['tls'], isTrue);
    });

    test('parses trojan:// URI', () {
      final result = parseProxyUri(
        'trojan://password@example.com:443#trtest',
      );
      expect(result, isNotNull);
      expect(result!['type'], 'trojan');
      expect(result['server'], 'example.com');
      expect(result['port'], 443);
      expect(result['password'], 'password');
    });

    test('returns null for unknown scheme', () {
      expect(parseProxyUri('ftp://example.com/file'), isNull);
    });

    test('parses hysteria2:// URI', () {
      final result = parseProxyUri('hysteria2://host:443#hy');
      expect(result, isNotNull);
      expect(result!['type'], 'hysteria2');
    });
  });

  group('decodeBase64Subscription', () {
    test('decodes valid base64 with multiple proxies', () {
      final ssBody1 = base64.encode(utf8.encode('aes-128-gcm:pass1@host1.com:443'));
      final ssBody2 = base64.encode(utf8.encode('aes-256-gcm:pass2@host2.com:8080'));
      final content = 'ss://$ssBody1#p1\nss://$ssBody2#p2\n';
      final encoded = base64.encode(utf8.encode(content));
      final result = decodeBase64Subscription(encoded);
      expect(result, isNotNull);
      expect(result, contains('proxies:'));
      expect(result, contains('p1'));
      expect(result, contains('p2'));
    });

    test('returns null when no valid proxies found', () {
      final content = 'not a proxy\njust text\n';
      final encoded = base64.encode(utf8.encode(content));
      final result = decodeBase64Subscription(encoded);
      expect(result, isNull);
    });

    test('handles single proxy', () {
      final ssBody = base64.encode(utf8.encode('aes-128-gcm:pass@host.com:443'));
      final content = 'ss://$ssBody#single\n';
      final encoded = base64.encode(utf8.encode(content));
      final result = decodeBase64Subscription(encoded);
      expect(result, isNotNull);
      expect(result, contains('single'));
    });

    test('skips empty lines and invalid entries', () {
      final ssBody = base64.encode(utf8.encode('aes-128-gcm:pass@host.com:443'));
      final content = '\n\nss://$ssBody#valid\n\nnot-a-uri\n';
      final encoded = base64.encode(utf8.encode(content));
      final result = decodeBase64Subscription(encoded);
      expect(result, isNotNull);
      expect(result, contains('valid'));
    });
  });

  group('parseShadowsocks', () {
    test('parses user@host:port format', () {
      final encoded = base64.encode(utf8.encode('aes-128-gcm:password'));
      final result = parseShadowsocks('$encoded@server.com:8080', 'ss1');
      expect(result, isNotNull);
      expect(result!['type'], 'ss');
      expect(result['server'], 'server.com');
      expect(result['port'], 8080);
      expect(result['cipher'], 'aes-128-gcm');
      expect(result['password'], 'password');
    });

    test('parses full base64 format', () {
      final full = base64.encode(utf8.encode('aes-256-ctr:pass@server.com:443'));
      final result = parseShadowsocks(full, 'ss2');
      expect(result, isNotNull);
      expect(result!['server'], 'server.com');
      expect(result['port'], 443);
    });

    test('returns null for invalid input', () {
      expect(parseShadowsocks('invalid', 'ss'), isNull);
    });
  });

  group('parseVmess', () {
    test('parses valid vmess base64 JSON', () {
      final json = jsonEncode({
        'add': 'example.com',
        'port': '443',
        'id': 'test-uuid',
        'aid': 0,
        'scy': 'auto',
      });
      final encoded = base64.encode(utf8.encode(json));
      final result = parseVmess(encoded, 'vm1');
      expect(result, isNotNull);
      expect(result!['type'], 'vmess');
      expect(result['server'], 'example.com');
      expect(result['uuid'], 'test-uuid');
    });

    test('returns null for invalid base64', () {
      expect(parseVmess('not-base64!!!', 'vm'), isNull);
    });

    test('returns null for invalid JSON', () {
      final encoded = base64.encode(utf8.encode('not json'));
      expect(parseVmess(encoded, 'vm'), isNull);
    });
  });

  group('parseVless', () {
    test('parses vless with tls', () {
      final result = parseVless(
        'uuid@example.com:443?security=tls#vl',
        'vl',
      );
      expect(result, isNotNull);
      expect(result!['tls'], isTrue);
    });

    test('parses vless without tls', () {
      final result = parseVless(
        'uuid@example.com:80#vl',
        'vl',
      );
      expect(result, isNotNull);
      expect(result!['tls'], isFalse);
    });
  });

  group('parseTrojan', () {
    test('parses valid trojan URI', () {
      final result = parseTrojan('pass@example.com:443#tr', 'tr');
      expect(result, isNotNull);
      expect(result!['type'], 'trojan');
      expect(result['password'], 'pass');
      expect(result['server'], 'example.com');
    });
  });
}
