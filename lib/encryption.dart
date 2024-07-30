import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

class EncryptionHelper {
  final Key key;
  final Encrypter encrypter;
  

  EncryptionHelper(String keyString, int ivLength)
      : key = Key.fromUtf8(keyString.padRight(32, '0').substring(0, 32)),
        encrypter = Encrypter(AES(Key.fromUtf8(keyString.padRight(32, '0').substring(0, 32)))) {}

  Encrypted encryptData(Uint8List data) {
    final base64Data = base64Encode(data);
    final iv = IV.fromLength(16);  // Ensure IV is always 16 bytes long
    return encrypter.encrypt(base64Data, iv: iv);
  }

  Uint8List decryptData(Encrypted encryptedData) {
    final iv = IV.fromLength(16);  // Ensure IV is the same as used for encryption
    final decryptedBase64 = encrypter.decrypt(encryptedData, iv: iv);
    return base64Decode(decryptedBase64);
  }
}
