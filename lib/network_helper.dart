import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:network_info_plus/network_info_plus.dart';

class NetworkHelper {
  static const String multicastAddress = '239.10.10.10';
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
          // Convert String 'DISCOVER' to Uint8List and send multicast packet
          Uint8List data = Uint8List.fromList('DISCOVER'.codeUnits);
          _socket!.send(data, InternetAddress(multicastAddress), port);
          logger.d('Sent multicast DISCOVER');
        } catch (e) {
          logger.e('Error sending multicast packet: $e');
        }
      }
    });
  }

  void listenForDiscovery() async {
  RawDatagramSocket.bind(InternetAddress.anyIPv4, 5555).then((socket) {
    socket.joinMulticast(InternetAddress('239.10.10.10'));
    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = socket.receive();
        if (datagram != null) {
          String message = String.fromCharCodes(datagram.data);
          if (message == 'DISCOVER') {
            socket.send(Uint8List.fromList('RESPONSE'.codeUnits), datagram.address, datagram.port);
          }
        }
      }
    });
  });
}


  void handleData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      Datagram? datagram = _socket!.receive();
      if (datagram != null) {
        String message = String.fromCharCodes(datagram.data);
        logger.d('Received message: $message from ${datagram.address}');
        if (message.trim() == 'RESPONSE') {
          String deviceAddress = datagram.address.address;
          if (!devices.contains(deviceAddress)) {
            devices.add(deviceAddress);
            _devicesController.add(devices.toList()); // Notify listeners
            logger.i('Added device: $deviceAddress');
          }
        }
      }
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

  Future<void> startReceiving([String? s]) async {
    String? savePath = await pickSaveDirectory();
    if (savePath == null) {
      logger.w('No directory selected for saving received files');
      return;
    }

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverSocket!.listen((Socket client) async {
        logger.i('Connection from ${client.remoteAddress.address}:${client.remotePort}');

        // Receive the file name and size
        List<int> data = [];
        await client.listen((List<int> event) {
          data.addAll(event);
        }).asFuture();

        String metadata = String.fromCharCodes(data);
        var parts = metadata.split(':');
        String fileName = parts[0];
        int fileSize = int.parse(parts[1]);

        // Receive the file data
        String filePath = path.join(savePath, fileName);
        File file = File(filePath);
        IOSink fileSink = file.openWrite();
        int bytesRead = 0;

        await for (List<int> data in client) {
          fileSink.add(data);
          bytesRead += data.length;
          if (bytesRead >= fileSize) break;
        }

        await fileSink.close();
        await client.close();
        logger.i('File received: $filePath');
      });
    } catch (e) {
      logger.e('Error starting server: $e');
    }
  }

  void stopReceiving() {
    _serverSocket?.close();
    _serverSocket = null;
    logger.i('Stopped receiving files');
  }
}
