import 'dart:convert';

import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

class EncryptionHelper {
  final Key key;
  final IV iv;
  final Encrypter encrypter;

  EncryptionHelper(String keyString, int ivLength)
      : key = Key.fromUtf8(keyString),
        iv = IV.fromLength(ivLength),
        encrypter = Encrypter(AES(Key.fromUtf8(keyString))) {}

  Encrypted encryptData(Uint8List data) {
    final base64Data = base64Encode(data);
    return encrypter.encrypt(base64Data, iv: iv);
  }

  Uint8List decryptData(Encrypted encryptedData) {
    final decryptedBase64 = encrypter.decrypt(encryptedData, iv: iv);
    return base64Decode(decryptedBase64);
  }
}
