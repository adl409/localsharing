import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:local_file_sharing/network_helper.dart'; // Make sure this path is correct

class SendFilePage extends StatefulWidget {
  @override
  _SendFilePageState createState() => _SendFilePageState();
}

class _SendFilePageState extends State<SendFilePage> {
  String? fileName; // To store the selected file name
  File? selectedFile; // To store the selected file
  String? selectedDevice; // To store the selected device

  NetworkHelper networkHelper = NetworkHelper(); // Instantiate network helper

  @override
  void initState() {
    super.initState();
    networkHelper.startMulticasting(); // Start multicasting when page initializes
  }

  @override
  void dispose() {
    networkHelper.stopMulticasting(); // Stop multicasting when page is disposed
    super.dispose();
  }

  void selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
        fileName = path.basename(result.files.single.path!);
      });
    } else {
      print('No file selected');
    }
  }

  void sendFile() async {
    if (selectedFile != null && selectedDevice != null) {
      try {
        await networkHelper.sendFile(selectedFile!, selectedDevice!);
        print('File sent: $fileName to $selectedDevice');
      } catch (e) {
        print('Failed to send file: $e');
      }
    } else {
      print('File or device not selected');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send File'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('Select File'),
              onPressed: selectFile,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 18),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            if (fileName != null)
              Text(
                'Selected file: $fileName',
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send File'),
              onPressed: sendFile,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 18),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Available Devices',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<List<String>>(
                        stream: networkHelper.devicesStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            List<String> discoveredDevices = snapshot.data!;
                            return ListView.builder(
                              itemCount: discoveredDevices.length,
                              itemBuilder: (context, index) {
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  child: ListTile(
                                    leading: const Icon(Icons.devices),
                                    title: Text(discoveredDevices[index]),
                                    onTap: () {
                                      setState(() {
                                        selectedDevice = discoveredDevices[index];
                                      });
                                      print('Device selected: ${discoveredDevices[index]}');
                                    },
                                  ),
                                );
                              },
                            );
                          } else {
                            return Center(child: CircularProgressIndicator());
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
