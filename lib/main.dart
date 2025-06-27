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

  // Regex para encontrar nossos placeholders, ex: [C:F567]
  final RegExp _controlCodeRegex = RegExp(r'\[C:([0-9A-Fa-f]+)\]');

  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _extractStrings();
    _extractPointers();
  }

  // Decodifica os bytes para uma string com placeholders
  String _decodeBytesToString(Uint8List bytes) {
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      int byte = bytes[i];
      // Heurística para detectar um código de controle (byte > 127)
      // O jogo parece usar códigos de 2 bytes começando com Fx
      if (byte >= 0xF0 && byte <= 0xFF && i + 1 < bytes.length) {
        int nextByte = bytes[i+1];
        // Adiciona como um placeholder
        sb.write('[C:${byte.toRadixString(16).toUpperCase()}${nextByte.toRadixString(16).toUpperCase()}]');
        i++; // Pula o próximo byte, pois já foi consumido
      } else if (byte >= 32 && byte <= 126) {
        // Caractere ASCII padrão
        sb.write(latin1.decode([byte]));
      } else {
        // Se for outro caractere especial, represente-o também
        sb.write('[C:${byte.toRadixString(16).toUpperCase()}]');
      }
    }
    return sb.toString();
  }

  // Codifica a string com placeholders de volta para os bytes originais
  Uint8List _encodeStringToBytes(String text) {
    List<int> byteList = [];
    int lastIndex = 0;

    for (final match in _controlCodeRegex.allMatches(text)) {
      // Adiciona o texto normal que veio antes do placeholder
      if (match.start > lastIndex) {
        byteList.addAll(latin1.encode(text.substring(lastIndex, match.start)));
      }

      // Converte o placeholder (ex: "F567") de volta para bytes
      String hexValue = match.group(1)!;
      byteList.addAll(hex.decode(hexValue));

      lastIndex = match.end;
    }

    // Adiciona qualquer texto restante após o último placeholder
    if (lastIndex < text.length) {
      byteList.addAll(latin1.encode(text.substring(lastIndex)));
    }

    return Uint8List.fromList(byteList);
  }

  void _extractStrings() {
    strings.clear();
    final Set<int> usedBytes = {};

    for (int i = 0; i < data.length; i++) {
      if (usedBytes.contains(i)) continue;

      // Um caractere válido inicia uma possível string (ASCII imprimível)
      if (data[i] >= 32 && data[i] <= 126) {
        final start = i;
        int end = i;

        // Uma string termina com um byte nulo (0x00)
        while (end < data.length && data[end] != 0) {
          end++;
        }

        if (end - start < 3) continue;

        final strBytes = data.sublist(start, end);
        // Usa nosso decodificador customizado
        String extractedString = _decodeBytesToString(strBytes);

        if (extractedString.trim().isEmpty) continue;

        strings[start] = extractedString;

        for (int j = start; j <= end; j++) {
          usedBytes.add(j);
        }
        i = end;
      }
    }
  }

  void _extractPointers() {
    pointers.clear();
    if (strings.isEmpty) return;

    // Procura em todo o arquivo
    for (int i = 0; i <= data.length - 4; i++) {
      // Lê um valor de 4 bytes (little-endian)
      int value = ByteData.sublistView(data, i).getUint32(0, Endian.little);
      // Se o valor corresponde ao endereço de início de uma string, é um ponteiro
      if (strings.containsKey(value)) {
        pointers[i] = value;
      }
    }
  }

  void editString(int offsetOfStringToEdit, String newText) {
    if (!strings.containsKey(offsetOfStringToEdit)) return;

    // 1. Calcular as diferenças usando o nosso ENCODER customizado
    final String oldText = strings[offsetOfStringToEdit]!;
    final Uint8List oldTextBytes = _encodeStringToBytes(oldText);
    final Uint8List newTextBytes = _encodeStringToBytes(newText);

    final int oldLengthInFile = oldTextBytes.length + 1;
    final int newLengthInFile = newTextBytes.length + 1;
    final int shiftAmount = newLengthInFile - oldLengthInFile;

    // 2. Construir o novo buffer de dados (newData)
    final Uint8List newData = Uint8List(data.length + shiftAmount);

    newData.setRange(0, offsetOfStringToEdit, data.sublist(0, offsetOfStringToEdit));

    newData.setRange(offsetOfStringToEdit, offsetOfStringToEdit + newTextBytes.length, newTextBytes);
    newData[offsetOfStringToEdit + newTextBytes.length] = 0x00; // Terminador nulo

    int originalDataTailStart = offsetOfStringToEdit + oldLengthInFile;
    int newDataTailStart = offsetOfStringToEdit + newLengthInFile;
    newData.setRange(newDataTailStart, newData.length, data.sublist(originalDataTailStart));

    // 3. Atualizar todos os ponteiros e strings que foram deslocados
    final Map<int, int> updatedStringOffsets = {};
    for (var entry in strings.entries) {
      int oldStringAddr = entry.key;
      updatedStringOffsets[oldStringAddr] = (oldStringAddr > offsetOfStringToEdit)
          ? oldStringAddr + shiftAmount
          : oldStringAddr;
    }

    final Map<int, int> updatedPointers = {};
    for (var entry in pointers.entries) {
      int oldPointerAddr = entry.key;
      int oldPointerValue = entry.value;

      int newPointerAddr = (oldPointerAddr > offsetOfStringToEdit) ? oldPointerAddr + shiftAmount : oldPointerAddr;
      int newPointerValue = (oldPointerValue > offsetOfStringToEdit) ? oldPointerValue + shiftAmount : oldPointerValue;

      updatedPointers[newPointerAddr] = newPointerValue;
    }

    // 4. Aplicar os valores dos ponteiros atualizados no `newData`
    for (var entry in updatedPointers.entries) {
      if (entry.key + 4 <= newData.length) {
        ByteData.sublistView(newData, entry.key).setUint32(0, entry.value, Endian.little);
      }
    }

    // 5. Atualizar o estado interno da classe
    this.data = newData;

    final Map<int, String> newStringsMap = {};
    for (var entry in strings.entries) {
      int newOffset = updatedStringOffsets[entry.key]!;
      String text = (entry.key == offsetOfStringToEdit) ? newText : entry.value;
      newStringsMap[newOffset] = text;
    }

    this.strings = newStringsMap;
    this.pointers = updatedPointers;

    var sortedEntries = strings.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    this.strings = Map.fromEntries(sortedEntries);
  }

  String exportHex() => hex.encode(data);
}

void main() {
  runApp(HexEditorApp());
}

class HexEditorApp extends StatefulWidget {
  @override
  State<HexEditorApp> createState() => _HexEditorAppState();
}

class _HexEditorAppState extends State<HexEditorApp> {
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