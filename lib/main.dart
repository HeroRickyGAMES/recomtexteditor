import 'package:flutter/material.dart';
import 'package:convert/convert.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class HexEditor {
  Uint8List data;
  Map<int, String> strings = {};
  Map<int, int> pointers = {};

  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _extractStrings();
    _extractPointers();
  }

  String _decodeCustomEncoding(List<int> buffer) {
    String result = utf8.decode(buffer, allowMalformed: true);
    return result.replaceAll('\u815C\u81F4', '----');
  }

  void _extractStrings() {
    strings.clear();
    int start = -1;
    List<int> buffer = [];

    for (int i = 0; i < data.length; i++) {
      if ((data[i] >= 32 && data[i] <= 126) || data[i] == 0x0A || data[i] == 0x0D) {
        if (start == -1) start = i;
        buffer.add(data[i]);
      } else if (i + 3 < data.length &&
          data[i] == 0x81 && data[i + 1] == 0x5C &&
          data[i + 2] == 0x81 && data[i + 3] == 0xF4) {
        if (start == -1) start = i;
        buffer.addAll([0x81, 0x5C, 0x81, 0xF4]);
        i += 3;
      } else {
        if (start != -1 && buffer.isNotEmpty) {
          strings[start] = _decodeCustomEncoding(buffer);
          buffer.clear();
          start = -1;
        }
      }
    }

    if (start != -1 && buffer.isNotEmpty) {
      strings[start] = _decodeCustomEncoding(buffer);
    }
  }

  void _extractPointers() {
    pointers.clear();
    for (int i = 0; i <= data.length - 4; i++) {
      int value = ByteData.sublistView(data, i).getUint32(0, Endian.little);
      if (strings.containsKey(value)) {
        pointers[i] = value;
      }
    }
  }

  void editString(int oldOffset, String newText) {
    if (!strings.containsKey(oldOffset)) return;

    Uint8List oldStringBytes = Uint8List.fromList(utf8.encode(strings[oldOffset]!));
    Uint8List newStringBytes = Uint8List.fromList(utf8.encode(newText));

    if (oldStringBytes.contains(0x81) && oldStringBytes.contains(0x5C) &&
        oldStringBytes.contains(0x81) && oldStringBytes.contains(0xF4)) {
      newStringBytes = Uint8List.fromList(newStringBytes + [0x81, 0x5C, 0x81, 0xF4]);
    } else {
      newStringBytes = Uint8List.fromList(newStringBytes + [0]);
    }

    int oldLength = oldStringBytes.length;
    int shiftAmount = newStringBytes.length - oldLength;
    int newSize = data.length + shiftAmount;

    if (newSize < 0) return; // Evita erro de tamanho negativo

    Uint8List newData = Uint8List(newSize);
    newData.setRange(0, oldOffset, data.sublist(0, oldOffset));
    newData.setRange(oldOffset, oldOffset + newStringBytes.length, newStringBytes);
    if (oldOffset + oldLength < data.length) {
      newData.setRange(oldOffset + newStringBytes.length, newSize, data.sublist(oldOffset + oldLength));
    }

    for (var entry in pointers.entries) {
      int ptrAddr = entry.key;
      int ptrValue = entry.value;
      if (ptrValue >= oldOffset) {
        ptrValue += shiftAmount;
        if (ptrAddr + 4 <= newSize) {
          ByteData.sublistView(newData).setUint32(ptrAddr, ptrValue, Endian.little);
        }
      }
    }

    data = newData;
    _extractStrings();
    _extractPointers();
  }

  String exportHex() => hex.encode(data);
}

void main() {
  runApp(HexEditorApp());
}

class HexEditorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: HexInputScreen(),
    );
  }
}

class HexInputScreen extends StatefulWidget {
  @override
  _HexInputScreenState createState() => _HexInputScreenState();
}

class _HexInputScreenState extends State<HexInputScreen> {
  TextEditingController hexController = TextEditingController();

  void _processHex() {
    String hexString = hexController.text.replaceAll(" ", "");
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => HexEditorScreen(hexString: hexString)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Inserir Hexadecimal")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                maxLines: null,
                controller: hexController,
                decoration: InputDecoration(
                  hintText: "Cole o hexadecimal aqui...",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.multiline,
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: _processHex,
                child: Text("Carregar"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//aqui

class HexEditorScreen extends StatefulWidget {
  final String hexString;
  HexEditorScreen({required this.hexString});

  @override
  _HexEditorScreenState createState() => _HexEditorScreenState();
}

class _HexEditorScreenState extends State<HexEditorScreen> {
  late HexEditor editor;
  String searchQuery = "";
  TextEditingController searchController = TextEditingController();
  int? selectedOffset;
  TextEditingController textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    editor = HexEditor(widget.hexString);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hex Editor"),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: editor.exportHex()));
            },
            icon: Icon(Icons.copy, color: Colors.white),
            label: Text("Copiar", style: TextStyle(color: Colors.white)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(50.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Pesquisar...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[800],
              ),
              onChanged: (query) {
                setState(() {
                  searchQuery = query.toLowerCase();
                });
              },
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: editor.strings.entries.where((entry) => entry.value.toLowerCase().contains(searchQuery)).length,
              itemBuilder: (context, index) {
                var filteredEntries = editor.strings.entries.where((entry) => entry.value.toLowerCase().contains(searchQuery)).toList();
                int offset = filteredEntries[index].key;
                String value = filteredEntries[index].value;
                return ListTile(
                  title: Text("Offset: 0x${offset.toRadixString(16).toUpperCase()} - $value"),
                  onTap: () {
                    setState(() {
                      selectedOffset = offset;
                      textController.text = value;
                    });
                  },
                );
              },
            ),
          ),
          Expanded(
            flex: 3,
            child: selectedOffset != null
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Editando String em Offset 0x${selectedOffset!.toRadixString(16)}"),
                  TextField(
                    maxLines: null,
                    minLines: 9,
                    controller: textController,
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (selectedOffset != null) {
                        setState(() {
                          editor.editString(selectedOffset!, textController.text);
                          selectedOffset = null;
                        });
                      }
                    },
                    child: Text("Salvar"),
                  ),
                ],
              ),
            )
                : Center(child: Text("Selecione uma string para editar")),
          ),
        ],
      ),
    );
  }
}