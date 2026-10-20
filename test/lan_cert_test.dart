import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portable_media_library/src/core/lan_cert.dart';

/// Generates the CA + server certificate in a temp folder; set CERT_OUT to keep
/// the PEM files for inspection with openssl.
void main() {
  test('generates CA and server certificate', () async {
    final tmp = await Directory.systemTemp.createTemp('lan_cert_test');
    addTearDown(() => tmp.delete(recursive: true));
    final cert = await LanCert.ensure(ips: ['192.168.0.63'], hostnames: ['testpc', 'testpc.local'], dir: tmp);
    final out = Directory(Platform.environment['CERT_OUT'] ?? tmp.path);
    await File('${out.path}/ca.pem').writeAsString(cert.caCertPem);
    await File('${out.path}/chain.pem').writeAsString(cert.serverChainPem);
    await File('${out.path}/key.pem').writeAsString(cert.serverKeyPem);
    // Dart's TLS stack must accept the pair
    cert.securityContext();
    expect(cert.caCertDer, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
