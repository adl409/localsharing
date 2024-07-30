import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart'; // Add `crypto` package dependency in `pubspec.yaml`

class EncryptionHelper {
  final encrypt.Key _key;
  final encrypt.IV _iv;

  EncryptionHelper(String keyString, String ivString)
      : _key = encrypt.Key.fromUtf8(keyString),
        _iv = encrypt.IV.fromBase64(ivString);

  // Encrypt data
  Uint8List encryptData(Uint8List data) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    final encrypted = encrypter.encryptBytes(data, iv: _iv);
    return encrypted.bytes;
  }

  // Decrypt data
  Uint8List decryptData(Uint8List encryptedData) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(encryptedData),
      iv: _iv,
    );
    return Uint8List.fromList(decrypted); // Convert List<int> to Uint8List
  }

  // Generate SHA-256 hash
  String generateHash(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  // Verify data integrity by comparing hashes
  bool verifyDataIntegrity(Uint8List data, String expectedHash) {
    final actualHash = generateHash(data);
    return actualHash == expectedHash;
  }
}
