import 'package:flutter/material.dart';
import 'package:convert/convert.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';

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

  final Map<String, List<int>> replacementToBytes = {
    '™ª': [0x99, 0xAA],
    '™¥': [0x99, 0xA5],
    '™–': [0x99, 0x96],
    '™›': [0x99, 0x9B],
    '™‡': [0x99, 0x87],
    '™¡': [0x99, 0xA1],
    '™§': [0x99, 0xA7],
    'ä': [0x99, 0xE4],
    'Ä': [0x99, 0xC4],
    'ô': [0x81, 0x5C, 0x81, 0xF4],
  };

  List<int> encodeWithCustomBytes(String text) {
    List<int> result = [];
    int i = 0;

    while (i < text.length) {
      bool replaced = false;

      for (final entry in replacementToBytes.entries) {
        final key = entry.key;
        if (text.substring(i).startsWith(key)) {
          result.addAll(entry.value);
          i += key.length;
          replaced = true;
          break;
        }
      }

      if (!replaced) {
        result.add(text.codeUnitAt(i)); // ISO 8859-1 / ASCII compatível
        i++;
      }
    }

    result.add(0); // null terminator
    return result;
  }

  //Aqui é aonde fica as conversões que o conversor não consegue ler na tradução
  void _sanitizeCustomSequences() {
    final replacements = {
      [0x99, 0xAA]: '™ª',
      [0x99, 0xA5]: '™¥',
      [0x99, 0x96]: '™–',
      [0x99, 0x9B]: '™›',
      [0x99, 0x87]: '™‡',
      [0x99, 0xA1]: '™¡',
      [0x99, 0xA7]: '™§',
      [0x99, 0xE4]: 'ä',
      [0x99, 0xC4]: 'Ä',
      [0x81, 0x5C, 0x81, 0xF4]: 'ô'
    };

    final newData = <int>[];
    int i = 0;
    while (i < data.length) {
      bool matched = false;

      for (final entry in replacements.entries) {
        final bytes = entry.key;
        if (i + bytes.length <= data.length &&
            const ListEquality().equals(data.sublist(i, i + bytes.length), bytes)) {
          final replacement = entry.value.codeUnits;
          newData.addAll(replacement);
          i += bytes.length;
          matched = true;
          break;
        }
      }

      if (!matched) {
        newData.add(data[i]);
        i++;
      }
    }

    data = Uint8List.fromList(newData);
  }

  String _readStringAtOffset(int offset) {
    final bytes = <int>[];
    while (offset < data.length && data[offset] != 0) {
      bytes.add(data[offset]);
      offset++;
    }

    // Converta de volta os bytes especiais para símbolos
    final specialBytesToChar = {
      [0x99, 0xAA]: '™ª', //ó
      [0x99, 0xA5]: '™¥', //í
      [0x99, 0x96]: '™–', //Ú
      [0x99, 0x9B]: '™›', //á
      [0x99, 0x87]: '™‡', //É
      [0x99, 0xA1]: '™¡', //é
      [0x99, 0xA7]: '™§', //ï
      [0x99, 0xE4]: 'ä', //ä
      [0x99, 0xC4]: 'Ä', //Ä
      [0x81, 0x5C, 0x81, 0xF4]: 'ô', //----
    };

    final result = StringBuffer();
    int i = 0;

    while (i < bytes.length) {
      bool matched = false;
      for (final entry in specialBytesToChar.entries) {
        final b = entry.key;
        if (i + b.length <= bytes.length &&
            const ListEquality().equals(bytes.sublist(i, i + b.length), b)) {
          result.write(entry.value);
          i += b.length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        result.writeCharCode(bytes[i]);
        i++;
      }
    }

    return result.toString();
  }


  void _extractStrings() {
    for (int i = 0; i < data.length - 1; i++) {
      if (data[i] != 0) {
        final str = _readStringAtOffset(i);
        if (str.isNotEmpty) {
          strings[i] = str;
          i += str.length; // avançar até o fim da string
        }
      }
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

    Uint8List newStringBytes = Uint8List.fromList(encodeWithCustomBytes(newText));
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
    _extractStrings();           // Primeiro extrai as strings
    _sanitizeCustomSequences(); // Depois sanitiza as strings extraídas
    _extractPointers();         // Por fim, extrai os ponteiros (opcionalmente)
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
                    "Offset: 0x${offset.toRadixString(16).toUpperCase()} - ${value.replaceAll('"ª', 'ó').replaceAll('":', "á").replaceAll('¯', 'ú').replaceAll('"¥', 'í').replaceAll('¨', 'ñ').replaceAll("", 'Á').replaceAll('"¡', "é").replaceAll('"', 'u').replaceAll("", 'Í').replaceAll("", 'Ó')}",
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