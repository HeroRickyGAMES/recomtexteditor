import 'package:flutter/material.dart';
import 'package:convert/convert.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:recomtexteditor/tradutor.dart';

class HexEditor {
  Uint8List data;
  Map<int, String> strings = {};
  Map<int, int> pointers = {};

  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _extractStrings();
    _extractPointers();
  }

  void _extractStrings() {  strings.clear();
    for (int i = 0; i < data.length; i++) {
      if (data[i] >= 32 && data[i] <= 126 || data[i] >= 160) {
        final start = i;
        while (i < data.length && data[i] != 0 && (data[i] >= 32 && data[i] <= 126 || data[i] >= 160)) {
          i++;
        }

        final end = i;
        if (end - start < 3) continue; // ignora strings muito curtas

        final strBytes = data.sublist(start, end);
        String extractedString = latin1.decode(strBytes);

        // Filtra caracteres suspeitos como você já faz
        if (_isSuspeita(extractedString)) continue;

        strings[start] = extractedString;
      }
    }
  }

  bool _isSuspeita(String s) {
    return s.contains(RegExp(r'[@ÿà¨\x01-\x1F§®¤]')) || s.length <= 2;
  }

  void _extractPointers() {
    pointers.clear();

    if (data.length < 4) {
      print("Arquivo muito pequeno para conter tabela de ponteiros.");
      return;
    }

    int pointerCount = ByteData.sublistView(data, 0, 4).getUint32(0, Endian.little);

    for (int i = 0; i < pointerCount; i++) {
      int pointerOffset = 4 + i * 4;
      if (pointerOffset + 4 > data.length) {
        print("Ponteiro fora do arquivo, parando leitura.");
        break;
      }

      int stringOffset = ByteData.sublistView(data, pointerOffset).getUint32(0, Endian.little);

      if (stringOffset < data.length) {
        pointers[pointerOffset] = stringOffset;
      }
    }
  }

  void editString(int oldOffset, String newText) {
    if (!strings.containsKey(oldOffset)) return;

    Uint8List newStringBytes =  Uint8List.fromList(latin1.encode(newText) + [0x00]);
    String oldText = strings[oldOffset]!;
    int oldLength = latin1.encode(oldText).length + 1; // real length in bytes
    int shiftAmount = 0;

    shiftAmount = newStringBytes.length - oldLength;

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

            ],
          ),
        ),
      ),floatingActionButton: ElevatedButton(onPressed: _processHex, child: Text("Carregar")),
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
    List<MapEntry<int, int>> orderedPointers = editor.pointers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)); // ordena pela ordem na tabela de ponteiros

    var filtered = orderedPointers.where((entry) {
      final string = editor.strings[entry.value];
      return string != null && string.toLowerCase().contains(searchQuery);
    }).toList();

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
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                int pointerOffset = filtered[index].key;
                int stringOffset = filtered[index].value;
                String value = editor.strings[stringOffset] ?? '';
                var entry = editor.strings.entries.elementAt(index);
                var filteredEntries = editor.strings.entries.where((entry) => entry.value.toLowerCase().contains(searchQuery)).toList();
                int offset = filteredEntries[index].key;
                return ListTile(
                  title: Text(
                      "Pointer @ 0x${pointerOffset.toRadixString(16).toUpperCase()} → Offset 0x${stringOffset.toRadixString(16).toUpperCase()} - $value",
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
                  Row(
                    children: [
                      IconButton(onPressed: () async {
                        textController.text = await TradutorClass(textController.text);
                      },
                          icon: Icon(Icons.translate)),
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