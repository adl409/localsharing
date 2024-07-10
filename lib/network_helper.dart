import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

class NetworkHelper {
  static const String multicastAddress = '239.10.10.10';
  static const int port = 5555;

  RawDatagramSocket? _socket;
  bool _isClosed = true;

  final _devicesController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get devicesStream => _devicesController.stream;

  List<String> devices = []; // List to store discovered devices

  Future<void> startMulticasting() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      _socket!.listen(handleData);
      _isClosed = false;
      _sendDiscoveryPacket();
    } catch (e) {
      print('Error starting multicast: $e');
    }
  }

  void stopMulticasting() {
    _isClosed = true;
    _socket?.close();
    _devicesController.close();
  }

  void _sendDiscoveryPacket() {
    Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isClosed) {
        timer.cancel();
      } else {
        _socket!.send('DISCOVER'.codeUnits, InternetAddress(multicastAddress), port);
      }
    });
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
            _devicesController.add(devices);
          }
        }
      }
    }
  }

  Future<void> sendFile(File file, String deviceAddress) async {
    try {
      // Open a TCP socket to the selected device
      final socket = await Socket.connect(deviceAddress, port);
      print('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');

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
      print('File sent successfully');
    } catch (e) {
      print('Error sending file: $e');
      throw e;
    }
  }

  ServerSocket? _serverSocket;

  Future<void> startReceiving(String savePath) async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverSocket!.listen((Socket client) async {
        print('Connection from ${client.remoteAddress.address}:${client.remotePort}');

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
        print('File received: $filePath');
      });
    } catch (e) {
      print('Error starting server: $e');
    }
  }

  void stopReceiving() {
    _serverSocket?.close();
    _serverSocket = null;
    print('Stopped receiving files');
  }
}
