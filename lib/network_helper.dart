import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart'; // Add crypto package dependency in pubspec.yaml

class NetworkHelper {
  static const String centralServerAddress = '130.18.64.98'; // Update as needed
  static const int centralServerPort = 8080; // Port for the central server

  RawDatagramSocket? _socket;
  bool _isClosed = true;

  final _devicesController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get devicesStream => _devicesController.stream;
  Function(File)? onFileReceived;

  List<String> devices = []; // List to store discovered devices

  Logger logger = Logger();
  final NetworkInfo _networkInfo = NetworkInfo();

  String? _saveDirectory; // Variable to store selected save directory

  // Hardcoded AES key and IV
  final encrypt.Key _key = encrypt.Key.fromUtf8('32-character-long-key-for-aes256'); // 256-bit key for AES
  final encrypt.IV _iv = encrypt.IV.fromLength(16); // 128-bit IV for AES

  ServerSocket? _serverSocket;

  Future<void> startDiscovery() async {
    try {
      final socket = await Socket.connect(centralServerAddress, centralServerPort);
      logger.i('Connected to central server at $centralServerAddress:$centralServerPort');

      // Send a discovery request
      socket.write('DISCOVER');
      await socket.flush();

      socket.listen((data) {
        // Handle server response
        String response = String.fromCharCodes(data).trim();
        if (response.startsWith('DEVICE:')) {
          String deviceAddress = response.substring('DEVICE:'.length);
          if (!devices.contains(deviceAddress)) {
            devices.add(deviceAddress);
            _devicesController.add(devices.toList());
          }
        }
      });

      // Close the socket when done
      await socket.close();
    } catch (e) {
      logger.e('Error during discovery: $e');
    }
  }

  Future<void> sendFile(File file, String deviceAddress, {bool encryptData = false}) async {
    try {
      final socket = await Socket.connect(deviceAddress, centralServerPort);
      logger.i('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');

      final fileName = path.basename(file.path);
      final fileSize = await file.length();

      // Compute SHA-256 hash of the file
      final fileBytes = await file.readAsBytes();
      final fileHash = generateHash(fileBytes);

      final metadata = jsonEncode({
        'fileName': fileName,
        'fileSize': fileSize,
        'isEncrypted': encryptData,
        'iv': _iv.base64, // Include IV in metadata
        'hash': fileHash // Include hash in metadata
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
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, centralServerPort);
      logger.i('Server started on ${_serverSocket!.address.address}:${_serverSocket!.port}');

      _serverSocket!.listen((Socket client) {
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
    await _serverSocket?.close();
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

  // Start the central server to handle discovery and file transfers
  Future<void> startCentralServer() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, centralServerPort);
      logger.i('Central server started on ${_serverSocket!.address.address}:${_serverSocket!.port}');

      _serverSocket!.listen((Socket client) async {
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

                  final file = File(path.join(_saveDirectory!, fileName!));
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
                  final receivedFile = File(path.join(_saveDirectory!, fileName!));
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
      });
    } catch (e) {
      logger.e('Error starting central server: $e');
    }
  }

  // Stop the central server
  Future<void> stopCentralServer() async {
    await _serverSocket?.close();
    logger.i('Stopped central server');
  }
}
