import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1.dart';

/// A local certificate authority plus a server certificate for this PC's
/// home-network addresses, so the phone page can use HTTPS (iOS only allows
/// motion sensors on secure pages). The phone trusts the CA once; server
/// certificates are re-issued from it whenever the PC's address changes.
///
/// Written by hand rather than with a certificate package because iOS requires
/// IP addresses as proper iPAddress SAN entries, which those packages can't emit.
class LanCert {
  final String caCertPem;
  final Uint8List caCertDer;
  final String serverChainPem;
  final String serverKeyPem;

  LanCert._(this.caCertPem, this.caCertDer, this.serverChainPem, this.serverKeyPem);

  static Directory get _dir => Directory(p.join(p.dirname(Platform.resolvedExecutable), 'lan_cert'));

  /// Loads the stored certificates, creating the CA on first use and a new
  /// server certificate when [ips] or [hostnames] aren't all covered.
  static Future<LanCert> ensure({required List<String> ips, required List<String> hostnames, Directory? dir}) async {
    dir ??= _dir;
    await dir.create(recursive: true);
    final caKeyFile = File(p.join(dir.path, 'ca.key'));
    final caCertFile = File(p.join(dir.path, 'ca.crt'));
    final srvKeyFile = File(p.join(dir.path, 'server.key'));
    final srvCertFile = File(p.join(dir.path, 'server.crt'));
    final sansFile = File(p.join(dir.path, 'server_sans.json'));

    if (!await caKeyFile.exists() || !await caCertFile.exists()) {
      final caKey = await Isolate.run(_generateKey);
      await caKeyFile.writeAsString(_pem('RSA PRIVATE KEY', _encodePrivateKey(caKey)));
      await caCertFile.writeAsString(_pem('CERTIFICATE', _buildCaCert(caKey)));
      // A new CA invalidates the old server certificate
      if (await srvCertFile.exists()) await srvCertFile.delete();
    }
    final caKey = _decodePrivateKey(_unpem(await caKeyFile.readAsString()));
    final caDer = _unpem(await caCertFile.readAsString());

    final wanted = {...ips, ...hostnames};
    Set<String> covered = {};
    try {
      covered = (jsonDecode(await sansFile.readAsString()) as List).cast<String>().toSet();
    } catch (_) {}
    if (!await srvCertFile.exists() || !await srvKeyFile.exists() || !covered.containsAll(wanted)) {
      final allIps = {...ips, '127.0.0.1'}.toList();
      final allNames = {...hostnames, 'localhost'}.toList();
      final srvKey = await Isolate.run(_generateKey);
      await srvKeyFile.writeAsString(_pem('RSA PRIVATE KEY', _encodePrivateKey(srvKey)));
      await srvCertFile.writeAsString(_pem('CERTIFICATE', _buildServerCert(caKey, caDer, srvKey, allIps, allNames)));
      await sansFile.writeAsString(jsonEncode([...allIps, ...allNames]));
    }

    final caPem = await caCertFile.readAsString();
    return LanCert._(caPem, caDer, (await srvCertFile.readAsString()) + caPem, await srvKeyFile.readAsString());
  }

  SecurityContext securityContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(serverChainPem))
    ..usePrivateKeyBytes(utf8.encode(serverKeyPem));

  // ─── Keys ──────────────────────────────────────────────────────────────────

  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateKey() {
    final rnd = FortunaRandom()..seed(KeyParameter(_randomBytes(32)));
    final gen = RSAKeyGenerator()
      ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64), rnd));
    final pair = gen.generateKeyPair();
    return AsymmetricKeyPair(pair.publicKey, pair.privateKey);
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// PKCS#1 RSAPrivateKey.
  static Uint8List _encodePrivateKey(AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> pair) {
    final k = pair.privateKey;
    final p = k.p!, q = k.q!, d = k.privateExponent!;
    return ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      ASN1Integer(k.modulus),
      ASN1Integer(pair.publicKey.publicExponent),
      ASN1Integer(d),
      ASN1Integer(p),
      ASN1Integer(q),
      ASN1Integer(d % (p - BigInt.one)),
      ASN1Integer(d % (q - BigInt.one)),
      ASN1Integer(q.modInverse(p)),
    ]).encode();
  }

  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _decodePrivateKey(Uint8List der) {
    final seq = ASN1Parser(der).nextObject() as ASN1Sequence;
    BigInt at(int i) => (seq.elements![i] as ASN1Integer).integer!;
    return AsymmetricKeyPair(
      RSAPublicKey(at(1), at(2)),
      RSAPrivateKey(at(1), at(3), at(4), at(5), at(2)),
    );
  }

  // ─── Certificates ──────────────────────────────────────────────────────────

  static final _sha256WithRsa = ASN1Sequence(elements: [
    ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'),
    ASN1Null(),
  ]);

  static ASN1Sequence _name(String cn) => ASN1Sequence(elements: [
        ASN1Set(elements: [
          ASN1Sequence(elements: [
            ASN1ObjectIdentifier.fromIdentifierString('2.5.4.10'), // O
            ASN1UTF8String(utf8StringValue: 'Portable Media Library'),
          ]),
        ]),
        ASN1Set(elements: [
          ASN1Sequence(elements: [
            ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'), // CN
            ASN1UTF8String(utf8StringValue: cn),
          ]),
        ]),
      ]);

  static String get _caName => 'PML Local CA (${Platform.localHostname})';

  static ASN1Sequence _publicKeyInfo(RSAPublicKey key) => ASN1Sequence(elements: [
        ASN1Sequence(elements: [
          ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'),
          ASN1Null(),
        ]),
        ASN1BitString(stringValues: _publicKeyBits(key))..unusedbits = 0,
      ]);

  static Uint8List _publicKeyBits(RSAPublicKey key) =>
      ASN1Sequence(elements: [ASN1Integer(key.modulus), ASN1Integer(key.publicExponent)]).encode();

  static Uint8List _keyId(RSAPublicKey key) => SHA1Digest().process(_publicKeyBits(key));

  static ASN1Sequence _extension(String oid, ASN1Object value, {bool critical = false}) => ASN1Sequence(elements: [
        ASN1ObjectIdentifier.fromIdentifierString(oid),
        if (critical) ASN1Boolean(true),
        ASN1OctetString(octets: value.encode()),
      ]);

  /// KeyUsage bit string with DER-minimal unused bits.
  static ASN1BitString _keyUsage(int bits) {
    var unused = 0;
    while (unused < 7 && (bits >> unused) & 1 == 0) {
      unused++;
    }
    return ASN1BitString(stringValues: [bits])..unusedbits = unused;
  }

  static Uint8List _sign(ASN1Sequence tbs, RSAPrivateKey key) {
    final tbsDer = tbs.encode();
    final signer = Signer('SHA-256/RSA')..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final sig = (signer.generateSignature(tbsDer) as RSASignature).bytes;
    // Concatenate raw DER so the signed TBS bytes go out exactly as signed
    final body = BytesBuilder()
      ..add(tbsDer)
      ..add(_sha256WithRsa.encode())
      ..add((ASN1BitString(stringValues: sig)..unusedbits = 0).encode());
    return _derSequence(body.takeBytes());
  }

  static Uint8List _derSequence(Uint8List content) {
    final n = content.length;
    final len = n < 0x80
        ? [n]
        : n < 0x100
            ? [0x81, n]
            : n < 0x10000
                ? [0x82, n >> 8, n & 0xff]
                : [0x83, n >> 16, (n >> 8) & 0xff, n & 0xff];
    return Uint8List.fromList([0x30, ...len, ...content]);
  }

  static ASN1Sequence _tbs({
    required ASN1Sequence issuer,
    required ASN1Sequence subject,
    required RSAPublicKey key,
    required int days,
    required List<ASN1Sequence> extensions,
  }) {
    final now = DateTime.now().toUtc();
    // Random positive 128-bit serial
    final serial = BigInt.parse(_randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    return ASN1Sequence(elements: [
      ASN1Sequence(tag: 0xA0, elements: [ASN1Integer(BigInt.two)]), // v3
      ASN1Integer(serial),
      _sha256WithRsa,
      issuer,
      ASN1Sequence(elements: [
        ASN1UtcTime(now.subtract(const Duration(days: 1))),
        ASN1UtcTime(now.add(Duration(days: days))),
      ]),
      subject,
      _publicKeyInfo(key),
      ASN1Sequence(tag: 0xA3, elements: [ASN1Sequence(elements: extensions)]),
    ]);
  }

  static Uint8List _buildCaCert(AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> ca) {
    final name = _name(_caName);
    return _sign(
      _tbs(
        issuer: name,
        subject: name,
        key: ca.publicKey,
        days: 3650,
        extensions: [
          _extension('2.5.29.19', ASN1Sequence(elements: [ASN1Boolean(true)]), critical: true), // CA:TRUE
          _extension('2.5.29.15', _keyUsage(0x06), critical: true), // keyCertSign, cRLSign
          _extension('2.5.29.14', ASN1OctetString(octets: _keyId(ca.publicKey))),
        ],
      ),
      ca.privateKey,
    );
  }

  static Uint8List _buildServerCert(
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> ca,
    Uint8List caDer,
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> server,
    List<String> ips,
    List<String> names,
  ) {
    return _sign(
      _tbs(
        issuer: _name(_caName),
        subject: _name(ips.first),
        key: server.publicKey,
        // iOS rejects TLS server certificates valid for more than 825 days
        days: 800,
        extensions: [
          _extension('2.5.29.19', ASN1Sequence(elements: []), critical: true), // CA:FALSE
          _extension('2.5.29.15', _keyUsage(0xA0), critical: true), // digitalSignature, keyEncipherment
          _extension('2.5.29.37', ASN1Sequence(elements: [ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.5.5.7.3.1')])), // serverAuth
          _extension('2.5.29.17', ASN1Sequence(elements: [
            for (final ip in ips) ASN1OctetString(octets: InternetAddress(ip).rawAddress, tag: 0x87), // iPAddress
            for (final n in names) ASN1IA5String(stringValue: n, tag: 0x82), // dNSName
          ])),
          _extension('2.5.29.14', ASN1OctetString(octets: _keyId(server.publicKey))),
          _extension('2.5.29.35', ASN1Sequence(elements: [
            ASN1OctetString(octets: _keyId(ca.publicKey), tag: 0x80), // keyIdentifier
          ])),
        ],
      ),
      ca.privateKey,
    );
  }

  // ─── PEM ───────────────────────────────────────────────────────────────────

  static String _pem(String label, Uint8List der) {
    final b64 = base64.encode(der);
    final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length))];
    return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
  }

  static Uint8List _unpem(String pem) =>
      base64.decode(pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join());
}
