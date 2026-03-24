import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium_libs/sodium_libs.dart';
import '../identity/identity_service.dart';

class CryptoService {
  CryptoService._();
  static final instance = CryptoService._();

  Sodium get _s => IdentityService.instance.sodium;
  SecureKey _sk(Uint8List b) => SecureKey.fromList(_s, b);

  Uint8List encryptMessage(String plaintext, Uint8List recipientPk) {
    final nonce = _s.randombytes.buf(24);
    final cipher = _s.crypto.box.easy(
      message: Uint8List.fromList(utf8.encode(plaintext)),
      nonce: nonce,
      publicKey: recipientPk,
      secretKey: _sk(IdentityService.instance.secretKey),
    );
    return Uint8List.fromList([...nonce, ...cipher]);
  }

  String decryptMessage(Uint8List payload, Uint8List senderPk) {
    final plain = _s.crypto.box.openEasy(
      cipherText: payload.sublist(24),
      nonce: payload.sublist(0, 24),
      publicKey: senderPk,
      secretKey: _sk(IdentityService.instance.secretKey),
    );
    return utf8.decode(plain);
  }

  Uint8List generateMediaKey() =>
      _s.crypto.secretBox.keygen().extractBytes();

  Uint8List encryptChunk(Uint8List chunk, Uint8List fileKey) {
    final nonce = _s.randombytes.buf(24);
    final cipher = _s.crypto.secretBox.easy(
      message: chunk,
      nonce: nonce,
      key: _sk(fileKey),
    );
    return Uint8List.fromList([...nonce, ...cipher]);
  }

  Uint8List decryptChunk(Uint8List payload, Uint8List fileKey) =>
      _s.crypto.secretBox.openEasy(
        cipherText: payload.sublist(24),
        nonce: payload.sublist(0, 24),
        key: _sk(fileKey),
      );

  Uint8List deriveBackupKey(String hexCode, Uint8List salt) =>
      _s.crypto.pwhash.call(
        outLen: 32,
        password: Int8List.fromList(utf8.encode(hexCode.toUpperCase())),
        salt: salt,
        opsLimit: _s.crypto.pwhash.opsLimitSensitive,
        memLimit: _s.crypto.pwhash.memLimitSensitive,
        alg: CryptoPwhashAlgorithm.argon2id13,
      ).extractBytes();

  Uint8List encryptBackup(Uint8List data, Uint8List key) {
    final nonce = _s.randombytes.buf(24);
    final cipher = _s.crypto.secretBox.easy(
      message: data,
      nonce: nonce,
      key: _sk(key),
    );
    return Uint8List.fromList([...nonce, ...cipher]);
  }

  Uint8List decryptBackup(Uint8List payload, Uint8List key) =>
      _s.crypto.secretBox.openEasy(
        cipherText: payload.sublist(24),
        nonce: payload.sublist(0, 24),
        key: _sk(key),
      );

  Uint8List hash(Uint8List data) =>
      _s.crypto.genericHash.call(outLen: 32, message: data);

  bool verifyHash(Uint8List data, Uint8List expected) {
    final actual = hash(data);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) diff |= actual[i] ^ expected[i];
    return diff == 0;
  }

  Uint8List randomBytes(int n) => _s.randombytes.buf(n);
}