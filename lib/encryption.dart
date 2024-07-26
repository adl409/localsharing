import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:async';

class EncryptionHelper {
  final encrypt.Encrypter _encrypter;
  final encrypt.IV _iv;

  EncryptionHelper(String key, String iv)
      : _encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key.fromBase64(key), mode: encrypt.AESMode.cbc)),
        _iv = encrypt.IV.fromBase64(iv);

  Stream<List<int>> encryptStream(Stream<List<int>> input) {
    return input.transform(StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        final encrypted = _encrypter.encryptBytes(Uint8List.fromList(data), iv: _iv);
        sink.add(encrypted.bytes);
      },
    ));
  }

  Stream<List<int>> decryptStream(Stream<List<int>> input) {
    return input.transform(StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        final decrypted = _encrypter.decryptBytes(encrypt.Encrypted(Uint8List.fromList(data)), iv: _iv);
        sink.add(decrypted);
      },
    ));
  }
}
