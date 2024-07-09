import 'dart:async';
import 'dart:io';

class NetworkHelper {
  static const String multicastAddress = '239.10.10.10';
  static const int port = 5555;

  RawDatagramSocket? _socket;
  bool _isClosed = true;

  StreamController<List<String>> _devicesController =
      StreamController<List<String>>.broadcast();

  Stream<List<String>> get devicesStream => _devicesController.stream;

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
          _devicesController.add([datagram.address.address]);
        }
      }
    }
  }
}

void main() async {
  NetworkHelper networkHelper = NetworkHelper();

  networkHelper.devicesStream.listen((List<String> devices) {
    print('Found device(s): $devices');
  });

  await networkHelper.startMulticasting();

  // Uncomment to stop multicasting after 30 seconds
  // await Future.delayed(Duration(seconds: 30));
  // networkHelper.stopMulticasting();
}
