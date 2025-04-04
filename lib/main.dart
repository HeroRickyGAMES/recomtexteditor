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
    _sanitizeCustomSequences();
    _extractStrings();
    _extractPointers();
  }

  void _sanitizeCustomSequences() {
    final pattern = [0x81, 0x5C, 0x81, 0xF4];
    final replacement = utf8.encode('----');

    List<int> sanitized = [];
    for (int i = 0; i < data.length;) {
      if (i + 3 < data.length &&
          data[i] == pattern[0] &&
          data[i + 1] == pattern[1] &&
          data[i + 2] == pattern[2] &&
          data[i + 3] == pattern[3]) {
        sanitized.addAll(replacement);
        i += 4;
      } else {
        sanitized.add(data[i]);
        i++;
      }
    }
    data = Uint8List.fromList(sanitized);
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
          strings[start] = utf8.decode(buffer, allowMalformed: true);
          buffer.clear();
          start = -1;
        }
      }
    }

    if (start != -1 && buffer.isNotEmpty) {
      strings[start] = utf8.decode(buffer, allowMalformed: true);
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

    Uint8List newStringBytes = Uint8List.fromList(utf8.encode(newText) + [0]);
    String oldText = strings[oldOffset]!;
    int oldLength = utf8.encode(oldText).length + 1; // real length in bytes
    int shiftAmount = newStringBytes.length - oldLength;

    // Criar novo buffer considerando realocação de todos os dados após o texto editado
    Uint8List newData = Uint8List(data.length + shiftAmount);
    int insertPos = 0;

    // Copiar dados antes do texto editado
    newData.setRange(0, oldOffset, data.sublist(0, oldOffset));
    insertPos += oldOffset;

    // Inserir novo texto
    newData.setRange(insertPos, insertPos + newStringBytes.length, newStringBytes);
    insertPos += newStringBytes.length;

    // Copiar o restante dos dados ajustando os offsets
    newData.setRange(insertPos, newData.length, data.sublist(oldOffset + oldLength));

    // Atualiza ponteiros (relocando todos que estavam APÓS o texto original)
    Map<int, int> updatedPointers = {};
    for (var entry in pointers.entries) {
      int pointerAddress = entry.key;
      int pointerValue = entry.value;

      // Recalcular valores dos ponteiros após a realocação
      if (pointerValue > oldOffset) {
        pointerValue += shiftAmount;
      }
      if (pointerAddress > oldOffset) {
        pointerAddress += shiftAmount;
      }

      updatedPointers[pointerAddress] = pointerValue;
    }

    data = newData;
    pointers = updatedPointers;

    // Aplicar os ponteiros atualizados na memória
    for (var entry in pointers.entries) {
      if (entry.key + 4 <= data.length) {
        ByteData.sublistView(data, entry.key).setUint32(0, entry.value, Endian.little);
      }
    }

    // Reextrair strings e ponteiros com base no novo conteúdo
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
              ),
              SizedBox(height: 10),
              ElevatedButton(onPressed: _processHex, child: Text("Carregar")),
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
                var entry = editor.strings.entries.elementAt(index);
                var filteredEntries = editor.strings.entries.where((entry) => entry.value.toLowerCase().contains(searchQuery)).toList();
                int offset = filteredEntries[index].key;
                String value = filteredEntries[index].value;
                return ListTile(
                  title: Text(
                      "Offset: 0x${offset.toRadixString(16).toUpperCase()} - $value",
                    style: TextStyle(
                      color: entry.value.contains('----') ? Colors.amber : Colors.white,
                      fontWeight: entry.value.contains('----') ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
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