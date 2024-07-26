// encryption_helper.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  final encrypt.Encrypter _encrypter;
  final encrypt.IV _iv;

  EncryptionHelper(String key, String iv)
      : _encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key.fromUtf8(key))),
        _iv = encrypt.IV.fromUtf8(iv);

  Uint8List encryptData(Uint8List data) {
    final encrypted = _encrypter.encryptBytes(data, iv: _iv);
    return encrypted.bytes;
  }

  List<int> decryptData(Uint8List data) {
    final decrypted = _encrypter.decryptBytes(encrypt.Encrypted(data), iv: _iv);
    return decrypted;
  }
}
