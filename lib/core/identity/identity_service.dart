import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium_libs/sodium_libs.dart';

class IdentityKeyPair {
  final Uint8List pk;
  final Uint8List sk;
  const IdentityKeyPair({required this.pk, required this.sk});
}

class IdentityService {
  IdentityService._();
  static final instance = IdentityService._();

  static const _kSK = 'identity_sk_v1';
  static const _kPK = 'identity_pk_v1';

  // Use basic storage without encryption as fallback
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false, // safer across devices
    ),
  );

  Sodium? _sodium;
  IdentityKeyPair? _kp;

  bool get isReady => _sodium != null && _kp != null;

  // Safe getters — return empty bytes if not initialized
  Uint8List get publicKey => _kp?.pk ?? Uint8List(32);
  Uint8List get secretKey => _kp?.sk ?? Uint8List(32);
  Sodium get sodium => _sodium!;

  Future<void> init() async {
    _sodium = await SodiumInit.init();

    try {
      final skB64 = await _storage.read(key: _kSK);
      if (skB64 != null) {
        _kp = IdentityKeyPair(
          sk: base64.decode(skB64),
          pk: base64.decode(await _storage.read(key: _kPK) ?? ''),
        );
      } else {
        await _generateNew();
      }
    } catch (e) {
      debugPrint('Key storage error: $e — generating new keypair');
      await _generateNew();
    }
  }

  Future<void> _generateNew() async {
    final kp = _sodium!.crypto.box.keyPair();
    final pk = kp.publicKey;
    final sk = kp.secretKey.extractBytes();
    try {
      await _storage.write(key: _kSK, value: base64.encode(sk));
      await _storage.write(key: _kPK, value: base64.encode(pk));
    } catch (e) {
      debugPrint('Could not persist keypair: $e');
    }
    _kp = IdentityKeyPair(pk: pk, sk: sk);
  }

  String get publicKeyBase58 => isReady ? Base58.encode(_kp!.pk) : 'not-ready';
  String get publicKeyShort {
    if (!isReady) return 'not-ready';
    final s = publicKeyBase58;
    return '${s.substring(0, 8)}...${s.substring(s.length - 8)}';
  }

  static Uint8List fromBase58(String s) => Base58.decode(s);
}

class Base58 {
  static const _alpha =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static String encode(Uint8List bytes) {
    BigInt num = BigInt.zero;
    for (final b in bytes) {
      num = num * BigInt.from(256) + BigInt.from(b);
    }
    var result = '';
    while (num > BigInt.zero) {
      final mod = (num % BigInt.from(58)).toInt();
      result = _alpha[mod] + result;
      num = num ~/ BigInt.from(58);
    }
    for (final b in bytes) {
      if (b == 0) result = '1$result'; else break;
    }
    return result;
  }

  static Uint8List decode(String str) {
    BigInt num = BigInt.zero;
    for (final c in str.split('')) {
      final idx = _alpha.indexOf(c);
      if (idx < 0) throw FormatException('Bad base58: $c');
      num = num * BigInt.from(58) + BigInt.from(idx);
    }
    final bytes = <int>[];
    while (num > BigInt.zero) {
      bytes.insert(0, (num % BigInt.from(256)).toInt());
      num = num ~/ BigInt.from(256);
    }
    for (final c in str.split('')) {
      if (c == '1') bytes.insert(0, 0); else break;
    }
    return Uint8List.fromList(bytes);
  }
}