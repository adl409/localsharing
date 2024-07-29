import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart'; // Add this import for SHA hashing

class EncryptionHelper {
  final Key key;
  final Encrypter encrypter;

  EncryptionHelper(String keyString, int ivLength)
      : key = Key.fromUtf8(keyString.padRight(32, '0').substring(0, 32)),
        encrypter = Encrypter(AES(Key.fromUtf8(keyString.padRight(32, '0').substring(0, 32))));

  Encrypted encryptData(Uint8List data) {
    // Generate SHA-256 hash of the data
    final hash = sha256.convert(data).bytes;

    // Combine hash and data
    final combinedData = Uint8List.fromList(hash + data);

    final base64Data = base64Encode(combinedData);
    final iv = IV.fromLength(16);  // Ensure IV is always 16 bytes long
    return encrypter.encrypt(base64Data, iv: iv);
  }

  Uint8List decryptData(Encrypted encryptedData) {
    final iv = IV.fromLength(16);  // Ensure IV is the same as used for encryption
    final decryptedBase64 = encrypter.decrypt(encryptedData, iv: iv);
    final decryptedData = base64Decode(decryptedBase64);

    // Split hash and data
    final hash = decryptedData.sublist(0, 32); // SHA-256 hash is 32 bytes long
    final originalData = decryptedData.sublist(32);

    // Verify the hash
    final calculatedHash = sha256.convert(originalData).bytes;
    if (!listEquals(hash, calculatedHash)) {
      throw Exception('Data integrity check failed');
    }

    return originalData;
  }

  bool listEquals(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}
