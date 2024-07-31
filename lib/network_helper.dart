import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart'; // Add `crypto` package dependency in `pubspec.yaml`

class NetworkHelper {
  static const String multicastAddress = '239.0.0.0';
  static const int port = 5555;

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
  final encrypt.Key _key = encrypt.Key.fromUtf8('32-character-long-key-for-aes256'); // Use a secure key in production
  final encrypt.IV _iv = encrypt.IV.fromUtf8('16-character-iv-123');

  Future<void> startMulticasting() async {
    try {
      String? wifiIP = await _networkInfo.getWifiIP();
      String? wifiName = await _networkInfo.getWifiName();
      logger.i('WiFi Name: $wifiName, IP: $wifiIP');

      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );

      // Join the multicast group
      _socket!.joinMulticast(InternetAddress(multicastAddress));
      logger.i('Joined multicast group $multicastAddress');

      _socket!.listen(handleData); // Listen for incoming datagrams
      _isClosed = false;
      _sendDiscoveryPacket();

      logger.i('Multicasting started successfully');
    } catch (e) {
      logger.e('Error starting multicast: $e');
      _socket?.close();
      _isClosed = true;
    }
  }

  void stopMulticasting() {
    _isClosed = true;
    _socket?.close();
    _devicesController.close();
    logger.i('Multicasting stopped');
  }

  void _sendDiscoveryPacket() {
    Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isClosed) {
        timer.cancel();
      } else {
        try {
          // Convert String 'DISCOVER' to Uint8List and send multicast packet
          Uint8List data = Uint8List.fromList('RESPONSE'.codeUnits);
          _socket!.send(data, InternetAddress(multicastAddress), port);
        } catch (e) {
          logger.e('Error sending multicast packet: $e');
        }
      }
    });
  }

  void listenForDiscovery() async {
    try {
      logger.i('Starting discovery listener...');
      RawDatagramSocket.bind(InternetAddress.anyIPv4, port).then((socket) {
        _socket = socket;
        logger.i('Socket bound to ${socket.address.address}:${socket.port}');

        socket.joinMulticast(InternetAddress(multicastAddress));
        logger.i('Joined multicast group $multicastAddress');

        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? datagram = socket.receive();
            if (datagram != null) {
              String message = String.fromCharCodes(datagram.data);
              if (message.trim() == 'RESPONSE') {
                socket.send(Uint8List.fromList('RESPONSE'.codeUnits), datagram.address, datagram.port);
              }
            }
          }
        });
      });
    } catch (e) {
      logger.e('Error listening for discovery: $e');
    }
  }

  void handleData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      Datagram? datagram = _socket!.receive();
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        if (message.trim() == 'RESPONSE') {
          String deviceAddress = datagram.address.address;
          if (!devices.contains(deviceAddress)) {
            devices.add(deviceAddress);
            _devicesController.add(devices.toList()); // Notify listeners
          }
        }
      }
    }
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

  Future<void> sendFile(File file, String deviceAddress, {bool encryptData = true}) async {
    try {
      final socket = await Socket.connect(deviceAddress, port);
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

  ServerSocket? _serverSocket;

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

  Future<void> startReceiving([Future<Null> Function(dynamic data, dynamic sender)? param0]) async {
    String? savePath = await pickSaveDirectory();
    if (savePath == null) {
      logger.w('No directory selected for saving received files');
      return;
    }

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
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
}
