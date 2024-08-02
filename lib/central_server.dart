import 'dart:io';
import 'dart:async';

class CentralServer {
  final int port;
  ServerSocket? _serverSocket;
  
  CentralServer(this.port);

  Future<void> start() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      print('Server is running on port $port');
      _serverSocket!.listen((Socket socket) {
        print('Connection from ${socket.remoteAddress.address}:${socket.remotePort}');
        socket.listen(
          (List<int> data) {
            final message = String.fromCharCodes(data).trim();
            print('Received: $message');
            socket.write('Message received: $message');
          },
          onDone: () {
            print('Client disconnected');
            socket.destroy();
          },
          onError: (error) {
            print('Error: $error');
          },
        );
      });
    } catch (e) {
      print('Failed to start server: $e');
    }
  }

  void stop() {
    _serverSocket?.close();
    print('Server stopped');
  }
}
