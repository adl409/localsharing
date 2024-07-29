import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:typed_data';

class EncryptionHelper {
  final encrypt.Encrypter _encrypter;
  final encrypt.IV _iv;

  EncryptionHelper(encrypt.Encrypter encrypter, encrypt.IV iv)
      : _encrypter = encrypter,
        _iv = iv;

  Uint8List encryptData(Uint8List data) {
    final encrypted = _encrypter.encryptBytes(data, iv: _iv);
    print('Encrypted data: ${encrypted.bytes}');
    return encrypted.bytes;
  }

  Uint8List decryptData(Uint8List encryptedData) {
    try {
      final encrypted = encrypt.Encrypted(encryptedData);
      final decrypted = _encrypter.decryptBytes(encrypted, iv: _iv);
      print('Decrypted data: $decrypted');
      return decrypted;
    } catch (e) {
      print('Decryption error: $e');
      throw Exception('Decryption error: $e');
    }
  }
}
