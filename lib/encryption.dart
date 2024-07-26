import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  final encrypt.Encrypter _encrypter;
  final encrypt.IV _iv;

  EncryptionHelper(String base64Key, String base64IV)
      : _encrypter = encrypt.Encrypter(
          encrypt.AES(
            encrypt.Key.fromBase64(base64Key),
            mode: encrypt.AESMode.cbc,
          ),
        ),
        _iv = encrypt.IV.fromBase64(base64IV);

  // Encrypt data stream
  Stream<List<int>> encryptStream(Stream<List<int>> inputStream) async* {
    await for (final chunk in inputStream) {
      final encryptedChunk = _encrypter.encryptBytes(chunk, iv: _iv);
      yield encryptedChunk.bytes; // Extract bytes from Encrypted object
    }
  }

  // Decrypt data stream
  Stream<List<int>> decryptStream(Stream<List<int>> inputStream) async* {
    final List<int> buffer = [];
    await for (final chunk in inputStream) {
      buffer.addAll(chunk);
      try {
        // Decrypt data in chunks
        final decryptedBytes = _encrypter.decryptBytes(Uint8List.fromList(buffer) as encrypt.Encrypted, iv: _iv);
        yield decryptedBytes;
        buffer.clear(); // Clear the buffer after processing
      } catch (e) {
        // Handle decryption errors (optional)
        print('Decryption error: $e');
      }
    }
  }

  // Utility function to convert base64 string to Uint8List
  Uint8List base64ToBytes(String base64String) {
    return base64.decode(base64String) as Uint8List;
  }

  // Utility function to convert Uint8List to base64 string
  String bytesToBase64(Uint8List bytes) {
    return base64.encode(bytes);
  }
}
