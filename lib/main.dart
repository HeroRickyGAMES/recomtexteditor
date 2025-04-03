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
    return buffer.map((hexValue) => String.fromCharCode(hexValue)).join();
  }

  void _extractStrings() {
    strings.clear();
    int start = -1;
    List<int> buffer = [];
    for (int i = 0; i < data.length; i++) {
      if ((data[i] >= 32 && data[i] <= 126) || data[i] == 0x0A || data[i] == 0x0D) {
        if (start == -1) start = i;
        buffer.add(data[i]);
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
    
    newText = newText.replaceAllMapped(RegExp(r'[äÄ]'), (match) {
      return match[0] == 'ä' ? 'ã' : 'Ã';
    });

    Uint8List newStringBytes = Uint8List.fromList(utf8.encode(newText) + [0]);
    int oldLength = strings[oldOffset]!.length + 1;

    if (newStringBytes.length > oldLength) {
      int newOffset = oldOffset;
      data = Uint8List.fromList([...data.sublist(0, newOffset), ...newStringBytes, ...data.sublist(newOffset + oldLength)]);

      Map<int, int> updatedPointers = {};
      pointers.forEach((key, value) {
        if (value == oldOffset) {
          updatedPointers[key] = newOffset;
        } else if (value > oldOffset) {
          updatedPointers[key] = value + (newStringBytes.length - oldLength);
        } else {
          updatedPointers[key] = value;
        }
      });
      pointers = updatedPointers;

      pointers.forEach((key, value) {
        ByteData.sublistView(data, key).setUint32(0, value, Endian.little);
      });
    } else {
      for (int i = 0; i < newStringBytes.length; i++) {
        data[oldOffset + i] = newStringBytes[i];
      }
      for (int i = newStringBytes.length; i < oldLength; i++) {
        data[oldOffset + i] = 0;
      }
    }

    _extractStrings();
    _extractPointers();
    print("Edição concluída: ${exportHex()}");
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