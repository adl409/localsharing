import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class NetworkHelper {
  static const String multicastAddress = '239.0.0.0';
  static const int port = 5555;

  RawDatagramSocket? _socket;
  bool _isClosed = true;

  final _devicesController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get devicesStream => _devicesController.stream;

  List<String> devices = []; // List to store discovered devices

  Logger logger = Logger();
  final NetworkInfo _networkInfo = NetworkInfo();

  String? _saveDirectory; // Variable to store selected save directory

  // AES encryption parameters
  static const String _aesKey = 'YOUR_AES_KEY'; // 16, 24, or 32 bytes
  static const String _aesIV = 'YOUR_AES_IV';   // 16 bytes

  final encrypt.Key _key = encrypt.Key.fromUtf8(_aesKey);
  final encrypt.IV _iv = encrypt.IV.fromUtf8(_aesIV);

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

  Future<void> sendFile(File file, String deviceAddress) async {
    try {
      final socket = await Socket.connect(deviceAddress, port);
      logger.i('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');

      final fileName = path.basename(file.path);
      final fileSize = await file.length();
      final encryptedBase64 = await encryptFileData(file);

      // Serialize metadata and encrypted data to JSON
      final metadata = jsonEncode({'fileName': fileName, 'fileSize': fileSize, 'encryptedData': encryptedBase64});
      socket.write('$metadata\n');

      // Wait for acknowledgment
      await socket.flush();

      await socket.close();
      logger.i('File sent successfully');
    } catch (e) {
      logger.e('Error sending file: $e');
      throw e;
    }
  }

  Future<String> encryptFileData(File file) async {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));

    // Read file content as bytes
    List<int> fileBytes = await file.readAsBytes();

    // Encrypt file content
    final encryptedBytes = encrypter.encryptBytes(fileBytes, iv: _iv);

    // Return encrypted data as Base64 string
    return encryptedBytes.base64;
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

  Future<void> startReceiving() async {
    String? savePath = await pickSaveDirectory();
    if (savePath == null) {
      logger.w('No directory selected for saving received files');
      return;
    }

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      logger.i('Server started on ${_serverSocket!.address.address}:${_serverSocket!.port}');

      _serverSocket!.listen((Socket client) {
        handleClientConnection(client, savePath!);
      });
    } catch (e) {
      logger.e('Error starting server: $e');
    }
  }

void handleClientConnection(Socket client, String savePath) async {
  logger.i('Connection from ${client.remoteAddress.address}:${client.remotePort}');

  try {
    final buffer = StringBuffer();
    bool metadataProcessed = false;
    String? fileName;
    int? fileSize;
    String? encryptedBase64;
    int bytesRead = 0;

    await client.listen(
      (List<int> data) async {
        if (!metadataProcessed) {
          buffer.write(String.fromCharCodes(data));
          if (buffer.toString().contains('\n')) {
            metadataProcessed = true;

            final metadataJson = buffer.toString().split('\n').first;
            logger.d('Received metadata: $metadataJson');

            final Map<String, dynamic> metadata = jsonDecode(metadataJson);
            fileName = metadata['fileName'];
            fileSize = metadata['fileSize'];
            encryptedBase64 = metadata['encryptedData'] ?? ''; // Handle nullable encryptedBase64

            if (fileName == null || fileSize == null || fileSize is! int) {
              logger.e('Invalid metadata format: $metadataJson');
              await client.close();
              return;
            }

            // Decrypt encrypted data if available
            if (encryptedBase64 != null && encryptedBase64!.isNotEmpty) {
              await decryptAndSaveFile(encryptedBase64!, fileName!, savePath);
            }

            // Remove metadata part from buffer
            buffer.clear();
          }
        }
      },
      onError: (error) async {
        logger.e('Error receiving file data: $error');
        await client.close();
      },
      onDone: () async {
        logger.i('File received: ${path.join(savePath, fileName!)}');
        await client.close();
      },
      cancelOnError: true,
    ).asFuture();
  } catch (e) {
    logger.e('Error processing client connection: $e');
    await client.close();
  }
}


  Future<void> decryptAndSaveFile(String encryptedBase64, String fileName, String savePath) async {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));

    // Decode Base64 string to encrypted bytes
    final encryptedBytes = encrypt.Encrypted.fromBase64(encryptedBase64);

    // Decrypt bytes to original file content
    final decryptedBytes = encrypter.decryptBytes(encryptedBytes, iv: _iv);

    // Write decrypted bytes to file
    File decryptedFile = File(path.join(savePath, fileName));
    await decryptedFile.writeAsBytes(decryptedBytes);
  }

  void stopReceiving() {
    _serverSocket?.close();
    _serverSocket = null;
    logger.i('Stopped receiving files');
  }
}
