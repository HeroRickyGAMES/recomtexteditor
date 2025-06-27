import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =======================================================================
// CLASSE PRINCIPAL DO EDITOR HEXADECIMAL
// =======================================================================
class HexEditor {
  Uint8List data;
  // Usar SplayTreeMap garante que os mapas estejam sempre ordenados pelas chaves (offsets)
  Map<int, String> strings = SplayTreeMap<int, String>();
  Map<int, int> pointers = SplayTreeMap<int, int>(); // {endereco_do_ponteiro: endereco_da_string}

  // REGRAS FIXAS baseadas na nossa análise
  static const int POINTER_TABLE_END = 0x0A74;
  static const int STRING_TABLE_START = 0x0A74;
  static const int POINTER_VALUE_OFFSET = 4;

  late final Map<int, String> _byteToChar;
  late final Map<String, int> _charToByte;

  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _buildCharMap();
    extractData();
  }

  // Função para mapear caracteres. Permanece correta.
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

  // Funções de encode/decode com suporte para placeholders.
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

  /// Extração de dados baseada nas regras do arquivo.
  void extractData() {
    strings.clear();
    pointers.clear();

    // 1. Encontra todos os textos na Tabela de Textos
    final Set<int> foundStringOffsets = {};
    for (int i = STRING_TABLE_START; i < data.length; i++) {
      if (foundStringOffsets.contains(i) || data[i] == 0) continue;

      final start = i;
      int end = i;
      while (end < data.length && data[end] != 0) {
        end++;
      }

      if (end > start) {
        final strBytes = data.sublist(start, end);
        strings[start] = _decodeBytesToString(strBytes);
        for (int j = start; j <= end; j++) {
          foundStringOffsets.add(j);
        }
        i = end;
      }
    }

    // 2. Encontra os ponteiros que apontam para os textos que achamos
    for (int i = 0; i < data.length - 3; i++) {
      int pointerValue = ByteData.sublistView(data, i).getUint32(0, Endian.little);
      int stringAddress = pointerValue +- POINTER_VALUE_OFFSET;

      if (strings.containsKey(stringAddress)) {
        pointers[i] = stringAddress;
      }
    }
  }

  /// EDIÇÃO FINAL: Reconstrói o arquivo com a lógica correta.
  void editString(int offsetOfStringToEdit, String newText) {
    if (!strings.containsKey(offsetOfStringToEdit)) return;

    // 1. Preparação
    final String oldText = strings[offsetOfStringToEdit]!;
    final Uint8List oldTextBytes = _encodeStringToBytes(oldText);
    final Uint8List newTextBytes = _encodeStringToBytes(newText);
    final int oldLengthInFile = oldTextBytes.length;
    final int newLengthInFile = newTextBytes.length;
    final int shiftAmount = newLengthInFile - oldLengthInFile;

    // 2. Criação do Novo Buffer
    final Uint8List newData = Uint8List(data.length + shiftAmount);

    // 3. Operação de Splice (Cortar, Inserir, Colar)
    // Parte 1: Copia tudo ANTES do texto editado
    newData.setRange(0, offsetOfStringToEdit, data.sublist(0, offsetOfStringToEdit));

    // Parte 2: Insere o NOVO texto
    newData.setRange(offsetOfStringToEdit, offsetOfStringToEdit + newTextBytes.length, newTextBytes);
    newData[offsetOfStringToEdit + newTextBytes.length] = 0x00;

    // Parte 3: Copia e DESLOCA todo o resto do arquivo
    int originalTailStart = offsetOfStringToEdit + oldLengthInFile;
    int newTailStart = offsetOfStringToEdit + newLengthInFile;
    if (originalTailStart < data.length) {
      newData.setRange(newTailStart, newData.length, data.sublist(originalTailStart));
    }

    // 4. Atualização dos Ponteiros
    final Map<int, int> newStringOffsets = {};
    for (int oldAddr in strings.keys) {
      if (oldAddr > offsetOfStringToEdit) {
        print('$oldAddr $shiftAmount');
        newStringOffsets[oldAddr] = oldAddr + shiftAmount;
      } else {
        newStringOffsets[oldAddr] = oldAddr;
      }
    }

    for (var pEntry in pointers.entries) {
      int pointerAddress = pEntry.key;
      int oldStringAddress = pEntry.value;

      int finalPointerAddress = pointerAddress;
      if (pointerAddress > offsetOfStringToEdit) {
        finalPointerAddress += shiftAmount;
      }

      if (newStringOffsets.containsKey(oldStringAddress) && finalPointerAddress + 4 <= newData.length) {
        int newStringAddress = newStringOffsets[oldStringAddress]!;
        int newPointerValue = newStringAddress - POINTER_VALUE_OFFSET;

        ByteData.sublistView(newData, finalPointerAddress).setUint32(0, newPointerValue, Endian.little);
      }
    }

    // 5. Finaliza a operação
    data = newData;
    extractData();
  }

  String exportHex() => hex.encode(data);
}


// =======================================================================
// CÓDIGO DA INTERFACE GRÁFICA (UI)
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
  int? selectedOffset;
  final TextEditingController textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    editor = HexEditor(widget.hexString);
  }

  void _onSave() {
    if (selectedOffset != null) {
      setState(() {
        editor.editString(selectedOffset!, textController.text);
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
    final filteredEntries = editor.strings.entries
        .where((entry) =>
        entry.value.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

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
                final entry = filteredEntries[index];
                final int offset = entry.key;
                final String value = entry.value;
                bool isSelected = selectedOffset == offset;

                return ListTile(
                  tileColor: isSelected ? Colors.blue.withOpacity(0.3) : null,
                  title: Text(
                    "0x${offset.toRadixString(16).toUpperCase()}: $value",
                    style: TextStyle(fontFamily: 'monospace', fontSize: 14),
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
                  Text(
                      "Editando String (Offset Original: 0x${selectedOffset!.toRadixString(16).toUpperCase()})"),
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
