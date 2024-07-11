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

      _socket!.listen(handleData);
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
          // Create a JSON object for metadata
          Map<String, dynamic> metadata = {
            'type': 'DISCOVER',
          };
          String jsonMetadata = json.encode(metadata);

          // Convert JSON string to Uint8List and send multicast packet
          Uint8List data = Uint8List.fromList(utf8.encode(jsonMetadata));
          _socket!.send(data, InternetAddress(multicastAddress), port);
          logger.d('Sent multicast DISCOVER');
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
              logger.d('Received discovery message: $message from ${datagram.address}');
              try {
                // Try to parse JSON from received data
                Map<String, dynamic> jsonData = json.decode(message);
                if (jsonData.containsKey('type') && jsonData['type'] == 'RESPONSE') {
                  socket.send(Uint8List.fromList(utf8.encode(message)), datagram.address, datagram.port);
                  logger.d('Sent RESPONSE to ${datagram.address}');
                }
              } catch (e) {
                logger.e('Error parsing JSON: $e');
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
        logger.d('Received message: $message from ${datagram.address}');
        try {
          // Try to parse JSON from received data
          Map<String, dynamic> jsonData = json.decode(message);
          if (jsonData.containsKey('type') && jsonData['type'] == 'RESPONSE') {
            String deviceAddress = datagram.address.address;
            if (!devices.contains(deviceAddress)) {
              devices.add(deviceAddress);
              _devicesController.add(devices.toList()); // Notify listeners
              logger.i('Added device: $deviceAddress');
            } else {
              logger.d('Device $deviceAddress already in list');
            }
          } else {
            logger.d('Message is not a RESPONSE: $message');
          }
        } catch (e) {
          logger.e('Error parsing JSON: $e');
        }
      } else {
        logger.d('Datagram is null');
      }
    } else if (event == RawSocketEvent.write) {
      logger.d('Socket is trying to write, but this handler is for read events.');
      // Handle write event if necessary
    } else {
      logger.d('Unhandled event type: $event');
    }
  }

  Future<void> sendFile(File file, String deviceAddress) async {
    try {
      // Open a TCP socket to the selected device
      final socket = await Socket.connect(deviceAddress, port);
      logger.i('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');

      // Send the file name and size first
      final fileName = path.basename(file.path);
      final fileSize = await file.length();
      socket.write('$fileName:$fileSize\n');

      // Wait for acknowledgment
      await socket.flush();

      // Send the file data
      final fileStream = file.openRead();
      await fileStream.pipe(socket);

      // Close the socket connection
      await socket.close();
      logger.i('File sent successfully');

      // Restart device discovery after file transfer
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
      _serverSocket!.listen((Socket client) async {
        logger.i('Connection from ${client.remoteAddress.address}:${client.remotePort}');

        try {
          // Receive the JSON metadata
          String metadata = await _receiveMetadata(client);
          logger.d('Received metadata: $metadata');

          // Parse JSON metadata
          Map<String, dynamic> jsonData = json.decode(metadata);
          // Handle jsonData as needed, for example:
          String type = jsonData['type'];

          // Implement the rest of the file receiving logic based on type if needed
          // For simplicity, assuming a direct file transfer after metadata check
          // Receive the file data
          await _receiveFileData(client, savePath);

          await client.close();
          logger.i('File received');
        } catch (e) {
          logger.e('Error processing client connection: $e');
          await client.close();
        }
      });
    } catch (e) {
      logger.e('Error starting server: $e');
    }
  }

  Future<String> _receiveMetadata(Socket client) async {
    Completer<String> completer = Completer<String>();
    List<int> data = [];

    client.listen((List<int> event) {
      data.addAll(event);
      String receivedData = utf8.decode(data);

      // Try to parse JSON from received data
      try {
        Map<String, dynamic> jsonData = json.decode(receivedData);
        if (jsonData.containsKey('type') && (jsonData['type'] == 'DISCOVER' || jsonData['type'] == 'RESPONSE')) {
          completer.complete(receivedData);
          client.close();
        }
      } catch (e) {
        // JSON parsing error, continue receiving
      }
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.completeError('Connection closed before metadata was fully received');
      }
    }, onError: (error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    return completer.future;
  }

  Future<void> _receiveFileData(Socket client, String savePath) async {
    // Implement your file data receiving logic here
    // This is simplified for demonstration
    // Example: Save received data to a file
    File file = File('$savePath/received_file.txt');
    IOSink fileSink = file.openWrite();

    await client.forEach((List<int> data) {
      fileSink.add(data);
    });

    await fileSink.close();
  }

  void stopReceiving() {
    _serverSocket?.close();
    _serverSocket = null;
    logger.i('Stopped receiving files');
  }
}
