// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:local_file_sharing/network_helper.dart';

class SendFilePage extends StatefulWidget {
  @override
  _SendFilePageState createState() => _SendFilePageState();
}

class _SendFilePageState extends State<SendFilePage> {
  final List<String> devices = [
    "Device 1",
    "Device 2",
    "Device 3",
    "Device 4",
    "Device 5"
  ]; // Sample device names

  String selectionMode = 'Single Device'; // To keep track of selection mode
  String? fileName; // To store the selected file name

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

  void reloadDevices() {
    // TODO: Implement device reloading logic
    print('Devices reloaded');
  }

  void selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if(result != null) {
      setState(() {
        fileName = path.basename(result.files.single.path!);
      });
    } else {
      print('No file selected');
    }
  }

  void sendFile() {
    // TODO: Implement file sending
    print('File sent: $fileName');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send File'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Select File'),
                  onPressed: selectFile,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, 50),
                    textStyle: const TextStyle(fontSize: 18),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
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
                    minimumSize: const Size(200, 50),
                    textStyle: const TextStyle(fontSize: 18),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
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
                    Row(
                      children: [
                        const Icon(Icons.arrow_drop_down),
                        const SizedBox(width: 10),
                        DropdownButton<String>(
                          value: selectionMode,
                          onChanged: (String? newValue) {
                            setState(() {
                              selectionMode = newValue!;
                            });
                          },
                          items: <String>['Single Device', 'Multiple Devices']
                              .map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: reloadDevices,
                        ),
                      ],
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
                                      // TODO: Implement device selection
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
