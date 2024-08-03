import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class NetworkHelper {
  static const int unicastPort = 5555; // Port for unicast communication

  RawDatagramSocket? _unicastSocket;
  bool _isUnicastRunning = false;

  final _devicesController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get devicesStream => _devicesController.stream;
  Function(File)? onFileReceived;

  List<String> devices = [];

  Logger logger = Logger();
  final NetworkInfo _networkInfo = NetworkInfo();

  String? _saveDirectory;

  final encrypt.Key _key = encrypt.Key.fromUtf8('32-character-long-key-for-aes256');
  final encrypt.IV _iv = encrypt.IV.fromLength(16);

  Future<void> startDiscovery() async {
    // Start unicast listening
    await _startUnicastListening();

    // Send unicast announcement
    await _sendUnicastAnnouncement();
  }

  Future<void> _startUnicastListening() async {
    if (_isUnicastRunning) return;

    try {
      final interface = await _networkInfo.getWifiIP();
      _unicastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 
        unicastPort,
        reuseAddress: true,
      );

      _isUnicastRunning = true;
      logger.i('Unicast listener started on port $unicastPort');

      _unicastSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _unicastSocket!.receive();
          if (datagram != null) {
            final message = String.fromCharCodes(datagram.data).trim();
            if (message.startsWith('DEVICE:')) {
              final deviceAddress = message.substring('DEVICE:'.length);
              if (!devices.contains(deviceAddress)) {
                devices.add(deviceAddress);
                _devicesController.add(devices.toList());
              }
            }
          }
        }
      });
    } catch (e) {
      logger.e('Error starting unicast listener: $e');
    }
  }

  Future<void> _sendUnicastAnnouncement() async {
    try {
      final message = 'DEVICE:${await _networkInfo.getWifiIP()}';
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 
        0, // Use any available port
        reuseAddress: true,
      );

      // You need to know the addresses of devices in the other subnet
      // Here we assume a list of known addresses in another subnet
      List<String> knownAddresses = ['10.45.0.18', '10.45.0.28', '10.45.0.24', '10.45.0.14', '10.45.0.10', '10.45.0.4', '10.13.16.191']; // Replace with actual addresses

      for (String address in knownAddresses) {
        final targetAddress = InternetAddress(address);
        socket.send(Uint8List.fromList(message.codeUnits), targetAddress, unicastPort);
        logger.i('Unicast announcement sent to $address: $message');
      }
    } catch (e) {
      logger.e('Error sending unicast announcement: $e');
    }
  }

  Future<void> stopDiscovery() async {
    _isUnicastRunning = false;
    _unicastSocket?.close();
    logger.i('Stopped unicast listening');
  }

  Future<void> sendFile(File file, String deviceAddress, {bool encryptData = true}) async {
    try {
      final socket = await Socket.connect(deviceAddress, unicastPort);
      logger.i('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');

      final fileName = path.basename(file.path);
      final fileSize = await file.length();

      final fileBytes = await file.readAsBytes();
      final fileHash = generateHash(fileBytes);

      final metadata = jsonEncode({
        'fileName': fileName,
        'fileSize': fileSize,
        'isEncrypted': encryptData,
        'iv': _iv.base64,
        'hash': fileHash
      });
      socket.write('$metadata\n');
      await socket.flush();

      final fileStream = file.openRead();
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));

      Stream<List<int>> encryptStream;
      if (encryptData) {
        encryptStream = fileStream.transform(StreamTransformer<List<int>, Uint8List>.fromHandlers(
          handleData: (data, sink) {
            final encrypted = encrypter.encryptBytes(Uint8List.fromList(data), iv: _iv);
            sink.add(encrypted.bytes);
          },
          handleDone: (sink) {
            sink.close();
            logger.i('Encryption completed.');
          }
        ));
        logger.i('Encrypting the file...');
      } else {
        encryptStream = fileStream;
      }

      await encryptStream.listen(
        (data) {
          socket.add(data);
        },
        onDone: () async {
          await socket.flush();
          await socket.close();
          logger.i(encryptData ? 'File encrypted and sent successfully.' : 'File sent successfully without encryption.');
        },
        onError: (e) {
          logger.e('Error sending file data: $e');
        },
        cancelOnError: true,
      ).asFuture();
    } catch (e) {
      logger.e('Error sending file: $e');
      throw e;
    }
  }

  Future<void> startReceiving() async {
    String? savePath = await pickSaveDirectory();
    if (savePath == null) {
      logger.w('No directory selected for saving received files');
      return;
    }

    try {
      final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, unicastPort);
      logger.i('Server started on ${serverSocket.address.address}:${serverSocket.port}');

      serverSocket.listen((Socket client) {
        handleClientConnection(client, savePath);
      });
    } catch (e) {
      logger.e('Error starting server: $e');
    }
  }

  Future<void> handleClientConnection(Socket client, String savePath) async {
    logger.i('Connection from ${client.remoteAddress.address}:${client.remotePort}');

    try {
      final buffer = StringBuffer();
      bool metadataProcessed = false;
      String? fileName;
      int? fileSize;
      IOSink? fileSink;
      int bytesRead = 0;
      bool? isEncrypted;
      encrypt.IV? iv;
      String? expectedHash;

      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));

      await client.listen(
        (data) async {
          if (!metadataProcessed) {
            buffer.write(String.fromCharCodes(data));
            if (buffer.toString().contains('\n')) {
              metadataProcessed = true;

              final metadataJson = buffer.toString().split('\n').first;
              logger.d('Received metadata: $metadataJson');

              final Map<String, dynamic> metadata = jsonDecode(metadataJson);
              fileName = metadata['fileName'];
              fileSize = metadata['fileSize'];
              isEncrypted = metadata['isEncrypted'];
              iv = encrypt.IV.fromBase64(metadata['iv']);
              expectedHash = metadata['hash'];

              final file = File(path.join(savePath, fileName!));
              fileSink = file.openWrite();
              buffer.clear();
            }
          } else {
            final fileData = data as Uint8List;

            if (isEncrypted!) {
              final decryptedData = encrypter.decryptBytes(encrypt.Encrypted(fileData), iv: iv!);
              fileSink!.add(decryptedData);
            } else {
              fileSink!.add(fileData);
            }

            bytesRead += fileData.length;
            if (bytesRead >= fileSize!) {
              await fileSink!.flush();
              await fileSink!.close();
              logger.i('File received and saved successfully.');
              final receivedFile = File(path.join(savePath, fileName!));
              final fileBytes = await receivedFile.readAsBytes();
              final receivedHash = generateHash(fileBytes);

              if (onFileReceived != null) {
                onFileReceived!(receivedFile);
              }
              if (verifyDataIntegrity(fileBytes, expectedHash!)) {
                logger.i('Data integrity verified successfully.');
              } else {
                logger.e('Data integrity verification failed.');
              }
              client.close();
            }
          }
        },
        onError: (error) {
          logger.e('Error receiving data: $error');
          client.close();
        },
      );
    } catch (e) {
      logger.e('Error handling client connection: $e');
      client.close();
    }
  }

  Future<void> stopReceiving() async {
    // Placeholder: Implement any necessary logic to stop receiving
    logger.i('Stopped receiving files');
  }

  Future<String?> pickSaveDirectory() async {
    if (_saveDirectory != null) {
      return _saveDirectory;
    }

    String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) {
      logger.w('Directory selection was canceled');
    } else {
      _saveDirectory = directoryPath;
    }
    return _saveDirectory;
  }

  // Calculate SHA-256 hash of data
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
