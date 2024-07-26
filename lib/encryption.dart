import 'dart:async';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  final encrypt.Key key;
  final encrypt.IV iv;

  EncryptionHelper(String keyBase64, String ivBase64)
      : key = encrypt.Key.fromBase64(keyBase64),
        iv = encrypt.IV.fromBase64(ivBase64);

  // Encrypt a stream of data
  Stream<Uint8List> encryptStream(Stream<List<int>> inputStream) {
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    return inputStream.transform(StreamTransformer<List<int>, Uint8List>.fromHandlers(
      handleData: (data, sink) {
        final encrypted = encrypter.encryptBytes(Uint8List.fromList(data), iv: iv);
        sink.add(encrypted.bytes);
      },
      handleError: (error, stackTrace, sink) {
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        sink.close();
      },
    ));
  }

  // Decrypt a stream of encrypted data
  Stream<Uint8List> decryptStream(Stream<List<int>> encryptedStream) {
    final decrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    return encryptedStream.transform(StreamTransformer<List<int>, Uint8List>.fromHandlers(
      handleData: (data, sink) {
        try {
          final decrypted = decrypter.decryptBytes(encrypt.Encrypted(Uint8List.fromList(data)), iv: iv);
          sink.add(Uint8List.fromList(decrypted));
        } catch (e) {
          print('Decryption error: $e');
          sink.addError(e);
        }
      },
      handleError: (error, stackTrace, sink) {
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        sink.close();
      },
    ));
  }
}
