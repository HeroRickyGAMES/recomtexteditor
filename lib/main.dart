import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =======================================================================
// CLASSE PRINCIPAL DO EDITOR HEXADECIMAL (LÓGICA CORRETA)
// =======================================================================
class HexEditor {
  Uint8List data;
  Map<int, String> strings = SplayTreeMap<int, String>();
  Map<int, int> pointers = SplayTreeMap<int, int>(); // {endereco_do_ponteiro: endereco_ABSOLUTO_da_string}

  // REGRAS FIXAS baseadas na nossa análise
  static const int POINTER_TABLE_START = 0x194;
  static const int POINTER_TABLE_END = 0x0A74;
  static const int STRING_TABLE_START = 0x0A74;

  late final Map<int, String> _byteToChar;
  late final Map<String, int> _charToByte;

  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _buildCharMap();
    extractData();
  }

  void _buildCharMap() {
    _byteToChar = {};
    for (int i = 32; i <= 126; i++) {
      _byteToChar[i] = String.fromCharCode(i);
    }
    const extendedChars =
        '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ¡¢£¤¥¦§¨©ª«¬®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ';
    for (int i = 0; i < extendedChars.length; i++) {
      _byteToChar[i + 128] = extendedChars[i];
    }
    _byteToChar[0x0A] = '\n';
    _charToByte = {for (var e in _byteToChar.entries) e.value: e.key};
  }

  String _decodeBytesToString(Uint8List bytes) {
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      int byte = bytes[i];
      if (_byteToChar.containsKey(byte)) {
        sb.write(_byteToChar[byte]);
      } else {
        if (byte >= 0xF0 && i + 1 < bytes.length) {
          int nextByte = bytes[i + 1];
          sb.write(
              '[C:${byte.toRadixString(16).toUpperCase()}${nextByte.toRadixString(16).toUpperCase()}]');
          i++;
        } else {
          sb.write('[B:${byte.toRadixString(16).toUpperCase()}]');
        }
      }
    }
    return sb.toString();
  }

  Uint8List _encodeStringToBytes(String text) {
    List<int> byteList = [];
    int lastIndex = 0;
    final RegExp allPlaceholdersRegex = RegExp(r'\[([CB]):([0-9A-Fa-f]+)\]');

    for (final match in allPlaceholdersRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        String normalText = text.substring(lastIndex, match.start);
        for (var charCode in normalText.runes) {
          var charStr = String.fromCharCode(charCode);
          if (_charToByte.containsKey(charStr)) {
            byteList.add(_charToByte[charStr]!);
          }
        }
      }
      String hexValue = match.group(2)!;
      byteList.addAll(hex.decode(hexValue));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      String normalText = text.substring(lastIndex);
      for (var charCode in normalText.runes) {
        var charStr = String.fromCharCode(charCode);
        if (_charToByte.containsKey(charStr)) {
          byteList.add(_charToByte[charStr]!);
        }
      }
    }
    return Uint8List.fromList(byteList);
  }

  /// Extração de dados LIDERADA POR PONTEIROS.
  void extractData() {
    strings.clear();
    pointers.clear();

    for (int i = POINTER_TABLE_START; i < POINTER_TABLE_END && i <= data.length - 4; i += 4) {
      int relativeOffset = ByteData.sublistView(data, i).getUint32(0, Endian.little);
      int absoluteAddress = STRING_TABLE_START + relativeOffset;
      pointers[i] = absoluteAddress;

      if (!strings.containsKey(absoluteAddress) && absoluteAddress < data.length) {
        int end = absoluteAddress;
        while (end < data.length && data[end] != 0) {
          end++;
        }
        if (end > absoluteAddress) {
          final strBytes = data.sublist(absoluteAddress, end);
          strings[absoluteAddress] = _decodeBytesToString(strBytes);
        } else {
          strings[absoluteAddress] = "";
        }
      }
    }
  }

  /// EDIÇÃO FINAL: Reconstrói o arquivo com a lógica de PONTEIROS RELATIVOS.
  void editString(int offsetOfStringToEdit, String newText) {
    if (!strings.containsKey(offsetOfStringToEdit)) return;

    final String oldText = strings[offsetOfStringToEdit]!;
    final Uint8List oldTextBytes = _encodeStringToBytes(oldText);
    final Uint8List newTextBytes = _encodeStringToBytes(newText);
    final int oldLengthInFile = oldTextBytes.length + 1;
    final int newLengthInFile = newTextBytes.length + 1;
    final int shiftAmount = newLengthInFile - oldLengthInFile;

    if (shiftAmount == 0) {
      data.setRange(
          offsetOfStringToEdit, offsetOfStringToEdit + newTextBytes.length, newTextBytes);
      strings[offsetOfStringToEdit] = newText;
      return;
    }

    final Uint8List newData = Uint8List(data.length + shiftAmount);
    newData.setRange(0, offsetOfStringToEdit, data.sublist(0, offsetOfStringToEdit));
    newData.setRange(
        offsetOfStringToEdit, offsetOfStringToEdit + newTextBytes.length, newTextBytes);
    newData[offsetOfStringToEdit + newTextBytes.length] = 0x00;
    int originalTailStart = offsetOfStringToEdit + oldLengthInFile;
    int newTailStart = offsetOfStringToEdit + newLengthInFile;
    if (originalTailStart < data.length) {
      newData.setRange(
          newTailStart, newData.length, data.sublist(originalTailStart));
    }

    pointers.forEach((pointerAddress, oldAbsoluteStringAddress) {
      int newAbsoluteStringAddress = oldAbsoluteStringAddress;

      if (oldAbsoluteStringAddress > offsetOfStringToEdit) {
        newAbsoluteStringAddress += shiftAmount;
      }

      int newRelativeOffset = newAbsoluteStringAddress - STRING_TABLE_START;

      if (pointerAddress < newData.length - 3) {
        ByteData.sublistView(newData, pointerAddress)
            .setUint32(0, newRelativeOffset, Endian.little);
      }
    });

    data = newData;

    extractData();
  }

  String exportHex() => hex.encode(data);
}

// =======================================================================
// CÓDIGO DA INTERFACE GRÁFICA (UI) - COM LAYOUT DA LISTA CORRIGIDO
// =======================================================================
void main() {
  runApp(HexEditorApp());
}

class HexEditorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
  final TextEditingController hexController = TextEditingController();

  void _processHex() {
    if (hexController.text.isEmpty) return;
    String hexString = hexController.text.replaceAll(RegExp(r'\s+'), "");
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => HexEditorScreen(hexString: hexString)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Inserir Hexadecimal")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                maxLines: null,
                minLines: null,
                expands: true,
                controller: hexController,
                decoration: InputDecoration(
                  hintText: "Cole o hexadecimal aqui...",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(onPressed: _processHex, child: Text("Analisar Arquivo")),
          ],
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
  final TextEditingController searchController = TextEditingController();
  int? selectedStringAddress;
  final TextEditingController textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    editor = HexEditor(widget.hexString);
  }

  void _onSave() {
    if (selectedStringAddress != null) {
      setState(() {
        editor.editString(selectedStringAddress!, textController.text);
        selectedStringAddress = null;
        textController.clear();
        searchController.clear();
        searchQuery = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Arquivo modificado e ponteiros realocados!"), duration: Duration(seconds: 2)),
      );
    }
  }

  void _onCopy() {
    Clipboard.setData(ClipboardData(text: editor.exportHex()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Hexadecimal copiado para a área de transferência!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = editor.pointers.entries.where((pointerEntry) {
      final stringAddress = pointerEntry.value;
      final stringValue = editor.strings[stringAddress] ?? "";
      return stringValue.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("Editor de Arquivo de Jogo"),
        actions: [
          TextButton.icon(
            onPressed: _onCopy,
            icon: Icon(Icons.copy, color: Colors.white),
            label: Text("Copiar Hex Final", style: TextStyle(color: Colors.white)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(50.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Pesquisar texto...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[850],
              ),
              onChanged: (query) => setState(() => searchQuery = query),
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: filteredEntries.length,
              itemBuilder: (context, index) {
                final pointerEntry = filteredEntries[index];
                final int pointerAddress = pointerEntry.key;
                final int stringAddress = pointerEntry.value;
                final String stringValue = editor.strings[stringAddress] ?? "[ERRO: String não encontrada]";

                bool isSelected = selectedStringAddress == stringAddress;

                // CORREÇÃO VISUAL FINAL: Usando title e subtitle para um layout robusto.
                return ListTile(
                  isThreeLine: true, // Garante espaço vertical para o subtítulo quebrar a linha.
                  tileColor: isSelected ? Colors.blue.withOpacity(0.3) : null,
                  title: Text(
                    "P: 0x${pointerAddress.toRadixString(16).toUpperCase().padLeft(4, '0')} -> S: 0x${stringAddress.toRadixString(16).toUpperCase()}",
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey[500]),
                  ),
                  subtitle: Text(
                    stringValue,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 15, color: Colors.white),
                  ),
                  onTap: () {
                    setState(() {
                      selectedStringAddress = stringAddress;
                      textController.text = stringValue;
                    });
                  },
                );
              },
            ),
          ),
          Expanded(
            flex: 3,
            child: selectedStringAddress != null
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      "Editando String no Endereço: 0x${selectedStringAddress!.toRadixString(16).toUpperCase()}"),
                  SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      maxLines: null,
                      minLines: null,
                      expands: true,
                      controller: textController,
                      decoration: InputDecoration(border: OutlineInputBorder()),
                      style: TextStyle(fontFamily: 'monospace', fontSize: 16),
                    ),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.save),
                        onPressed: _onSave,
                        label: Text("Salvar e Realocar Ponteiros"),
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
