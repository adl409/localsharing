import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:network_info_plus/network_info_plus.dart';

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
          // logger.d('Sent multicast RESPONSE');
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
              // logger.d('Received discovery message: $message from ${datagram.address}');
              if (message.trim() == 'RESPONSE') {
                socket.send(Uint8List.fromList('RESPONSE'.codeUnits), datagram.address, datagram.port);
                // logger.d('Sent RESPONSE to ${datagram.address}');
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
        // logger.d('Received message: $message from ${datagram.address}');
        if (message.trim() == 'RESPONSE') {
          String deviceAddress = datagram.address.address;
          if (!devices.contains(deviceAddress)) {
            devices.add(deviceAddress);
            _devicesController.add(devices.toList()); // Notify listeners
            // logger.i('Added device: $deviceAddress');
          } else {
            // logger.d('Device $deviceAddress already in list');
          }
        } else {
          logger.d('Message is not a RESPONSE: $message');
        }
      } else {
        logger.d('Datagram is null');
      }
    } else if (event == RawSocketEvent.write) {
      logger.d('Socket is trying to write, but this handler is for read events.');
      // Handle write event if necessary
    } else {
      // logger.d('Unhandled event type: $event');
    }
  }

  Future<void> sendFile(File file, String deviceAddress) async {
    try {
      final socket = await Socket.connect(deviceAddress, port);
      logger.i('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');

      final fileName = path.basename(file.path);
      final fileSize = await file.length();

      // Serialize metadata to JSON
      final metadata = jsonEncode({'fileName': fileName, 'fileSize': fileSize});
      socket.write('$metadata\n');

      // Wait for acknowledgment
      await socket.flush();

      // Send the file data
      final fileStream = file.openRead();
      await fileStream.pipe(socket);

      await socket.close();
      logger.i('File sent successfully');

      _sendDiscoveryPacket();
    } catch (e) {
      logger.e('Error sending file: $e');
      throw e;
    }
  }

  ServerSocket? _serverSocket;

  Future<String?> pickSaveDirectory() async {
    String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) {
      logger.w('Directory selection was canceled');
    }
    return directoryPath;
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
      // Receive the metadata
      String? metadataJson = await _receiveMetadata(client);
      logger.d('Received metadata: $metadataJson');

      if (metadataJson == null) {
        logger.e('Invalid metadata received');
        await client.close();
        return;
      }

      // Deserialize the metadata
      final Map<String, dynamic> metadata = jsonDecode(metadataJson);
      final String? fileName = metadata['fileName'];
      final dynamic fileSize = metadata['fileSize'];

      if (fileName == null || fileSize == null || fileSize is! int) {
        logger.e('Invalid metadata format: $metadataJson');
        await client.close();
        return;
      }

      // Receive the file data
      String filePath = path.join(savePath, fileName);
      await _receiveFileData(client, filePath, fileSize);

      logger.i('File received: $filePath');
    } catch (e) {
      logger.e('Error processing client connection: $e');
    } finally {
      await client.close();
    }
  }

  Future<String?> _receiveMetadata(Socket client) async {
    Completer<String?> completer = Completer<String?>();
    StringBuffer buffer = StringBuffer();
    bool metadataReceived = false;

    StreamSubscription<List<int>>? subscription;
    subscription = client.listen(
      (List<int> data) {
        String receivedString = String.fromCharCodes(data);
        buffer.write(receivedString);

        // Attempt to extract JSON metadata
        try {
          // Regular expression to find JSON object followed by newline
          final jsonMatch = RegExp(r'\{.*?\}\n').firstMatch(buffer.toString());
          if (jsonMatch != null) {
            final metadataString = jsonMatch.group(0)!;
            metadataReceived = true;
            completer.complete(metadataString);
            subscription?.cancel(); // Stop listening once metadata is received
          }
        } catch (e) {
          // Handle JSON parse error
          if (!metadataReceived) {
            completer.complete(null);
          }
        }
      },
      onError: (error) {
        completer.completeError(error);
      },
      onDone: () {
        if (!metadataReceived) {
          completer.complete(null);
        }
      },
      cancelOnError: true,
    );

    try {
      return await completer.future;
    } catch (e) {
      logger.e('Error receiving metadata: $e');
      return null;
    }
  }

  Future<void> _receiveFileData(Socket client, String filePath, int fileSize) async {
    File file = File(filePath);
    IOSink fileSink = file.openWrite();
    int bytesRead = 0;

    StreamSubscription<List<int>>? subscription;
    subscription = client.listen(
      (List<int> data) {
        bytesRead += data.length;
        fileSink.add(data);
        if (bytesRead >= fileSize) {
          subscription?.cancel(); // Stop listening once the file is completely received
        }
      },
      onError: (error) async {
        logger.e('Error receiving file data: $error');
        await fileSink.close();
        await file.delete(); // Clean up the partially written file
      },
      onDone: () async {
        await fileSink.close();
        if (bytesRead < fileSize) {
          logger.w('File transfer incomplete. Expected $fileSize bytes, but received $bytesRead bytes.');
        }
      },
      cancelOnError: true,
    );

    await subscription.asFuture(); // Await the completion of the stream
  }

  void stopReceiving() {
    _serverSocket?.close();
    _serverSocket = null;
    logger.i('Stopped receiving files');
  }
}
