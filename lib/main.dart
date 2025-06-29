import 'dart:collection';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:translator_plus/translator_plus.dart';

// =======================================================================
// CLASSE DE TRADUÇÃO
// =======================================================================
// Programado por HeroRickyGAMES com a ajuda de Deus!
final translator = GoogleTranslator();

Future<String> TradutorClass(String Texto) async {
  try {
    if (Texto.trim().isEmpty) {
      return "";
    }
    final translation = await translator.translate(Texto, from: 'en', to: 'pt');
    return translation.text;
  } catch (e) {
    print("Erro na tradução: $e");
    return Texto; // Retorna o texto original em caso de erro
  }
}

// =======================================================================
// CLASSE PRINCIPAL DO EDITOR HEXADECIMAL (LÓGICA INTELIGENTE)
// =======================================================================
class HexEditor {
  Uint8List data;
  Map<int, String> strings = SplayTreeMap<int, String>();
  Map<int, int> pointers = SplayTreeMap<int, int>(); // {endereco_do_ponteiro: endereco_ABSOLUTO_da_string}

  // Offsets fixos no header onde as informações importantes são encontradas.
  static const int HEADER_POINTER_TABLE_START_OFFSET = 0x08;
  static const int HEADER_POINTER_BASE_ADDRESS_OFFSET = 0x0C;

  // Variáveis que serão preenchidas dinamicamente a partir do header.
  late int pointerTableStart;
  late int pointerTableEnd;
  late int pointerBaseAddress;

  late final Map<int, String> _byteToChar;
  late final Map<String, int> _charToByte;

  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _buildCharMap();
    _analyzeHeader(); // Analisa o header para encontrar os offsets dinamicamente.
    extractData();
  }

  /// NOVO MÉTODO INTELIGENTE: Analisa o header do arquivo para encontrar os offsets.
  void _analyzeHeader() {
    try {
      // Lê os endereços diretamente do header do arquivo.
      pointerTableStart = data.buffer.asByteData().getUint32(HEADER_POINTER_TABLE_START_OFFSET, Endian.little) + 4;
      pointerBaseAddress = data.buffer.asByteData().getUint32(HEADER_POINTER_BASE_ADDRESS_OFFSET, Endian.little);

      // A lógica consistente mostra que o fim da tabela de ponteiros é 4 bytes após a base.
      pointerTableEnd = pointerBaseAddress + 4;

      print("--- Análise do Header ---");
      print("Tabela de Ponteiros Inicia em: 0x${pointerTableStart.toRadixString(16)}");
      print("Tabela de Ponteiros Termina em: 0x${pointerTableEnd.toRadixString(16)}");
      print("Base dos Ponteiros: 0x${pointerBaseAddress.toRadixString(16)}");
      print("--------------------------");

    } catch (e) {
      print("Erro ao analisar o header. Usando valores de fallback. Erro: $e");
      // Fallback para o arquivo original em caso de erro.
      pointerTableStart = 0x194;
      pointerTableEnd = 0x0A74;
      pointerBaseAddress = 0x0A70;
    }
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

    // CORREÇÃO: Força o mapeamento correto de caracteres especiais single-byte
  }

  String _decodeBytesToString(Uint8List bytes) {

    StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      int byte1 = bytes[i];

      // Lógica para caracteres de 2 bytes
      if (byte1 == 0x99 && i + 1 < bytes.length) {
        int byte2 = bytes[i+1];
        String specialChar = "";
        switch (byte2) {
          case 0xA1: specialChar = "ê"; break;
          case 0xA5: specialChar = "í"; break;
          case 0xAA: specialChar = "ó"; break;
          case 0x9B: specialChar = "á"; break;
          case 0x96: specialChar = "Ú"; break;
          case 0xA7: specialChar = "ï"; break;
          case 0x5F: specialChar = "ã"; break;
          case 0x23: specialChar = "Ç"; break;
          case 0x5C: specialChar = "ç"; break;
        }

        if (specialChar.isNotEmpty) {
          sb.write(specialChar);
          i++; // Pula o segundo byte
          continue;
        }
      }

      // Lógica para placeholders e caracteres de 1 byte
      if (_byteToChar.containsKey(byte1)) {
        sb.write(_byteToChar[byte1]);
      } else {
        if (byte1 >= 0xF0 && i + 1 < bytes.length) {
          int nextByte = bytes[i + 1];
          sb.write(
              '[C:${byte1.toRadixString(16).toUpperCase()}${nextByte.toRadixString(16).toUpperCase()}]');
          i++;
        } else {
          sb.write('[B:${byte1.toRadixString(16).toUpperCase()}]');
        }
      }
    }
    return sb.toString();
  }

  Uint8List _encodeStringToBytes(String text) {

    List<int> byteList = [];
    int lastIndex = 0;

    // Regex para encontrar placeholders E caracteres especiais de 2 bytes
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
    }
    for (int i = 0; i < text.length; i++) {
      String charStr = text[i];
      bool isSpecial = false;

      // Lógica para codificar os caracteres especiais de 2 bytes
      switch(charStr) {
        case 'ç': byteList.addAll([0x99, 0x9F]); isSpecial = true; break;
        case 'ã': byteList.addAll([0x99, 0x9D]); isSpecial = true; break;
        case 'â': byteList.addAll([0x99, 0x9C]); isSpecial = true; break;
        case 'ê': byteList.addAll([0x99, 0xA1]); isSpecial = true; break;
        case 'í': byteList.addAll([0x99, 0xA5]); isSpecial = true; break;
        case 'ó': byteList.addAll([0x99, 0xAA]); isSpecial = true; break;
        case 'á': byteList.addAll([0x99, 0x9B]); isSpecial = true; break;
        case 'ú': byteList.addAll([0x99, 0x96]); isSpecial = true; break;
        case 'ï': byteList.addAll([0x99, 0xA7]); isSpecial = true; break;
        case 'Ó': byteList.addAll([0x99, 0x90]); isSpecial = true; break;
        case 'Ç': byteList.addAll([0x99, 0x7F]); isSpecial = true; break;
        case 'Ã': byteList.addAll([0x99, 0x7D]); isSpecial = true; break;
      }

      if(isSpecial){
        continue;
      }

      // Lógica para placeholders e caracteres de 1 byte
      if (_charToByte.containsKey(charStr)) {
        byteList.add(_charToByte[charStr]!);
      }
    }
    return Uint8List.fromList(byteList);
  }

  void extractData() {
    strings.clear();
    pointers.clear();

    for (int i = pointerTableStart; i < pointerTableEnd && i <= data.length - 4; i += 4) {
      int relativeOffset = data.buffer.asByteData().getUint32(i, Endian.little);
      int absoluteAddress = pointerBaseAddress + relativeOffset;

      if (absoluteAddress < data.length) {
        pointers[i] = absoluteAddress;

        if (!strings.containsKey(absoluteAddress)) {
          int end = data.indexOf(0, absoluteAddress);
          if (end == -1) { end = data.length; }

          final strBytes = data.sublist(absoluteAddress, end);
          strings[absoluteAddress] = _decodeBytesToString(strBytes);
        }
      }
    }
  }

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

      int newRelativeOffset = newAbsoluteStringAddress - pointerBaseAddress;

      if (pointerAddress < newData.length - 3) {
        newData.buffer.asByteData().setUint32(pointerAddress, newRelativeOffset, Endian.little);
      }
    });

    data = newData;
    _analyzeHeader();
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
        title: Text("Kingdom Hearts RECOM PC TextEditor"),
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
            child: filteredEntries.isEmpty
                ? Center(child: Text("Nenhuma string encontrada.\nVerifique se o arquivo é compatível."))
                : ListView.separated(
              itemCount: filteredEntries.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[800]),
              itemBuilder: (context, index) {
                final pointerEntry = filteredEntries[index];
                final int pointerAddress = pointerEntry.key;
                final int stringAddress = pointerEntry.value;
                final String stringValue = editor.strings[stringAddress] ?? "[ERRO: String não encontrada]";

                bool isSelected = selectedStringAddress == stringAddress;

                return ListTile(
                  tileColor: isSelected ? Colors.blue.withOpacity(0.3) : Colors.transparent,
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
                      IconButton(onPressed: () async {
                        textController.text = await TradutorClass(textController.text);
                      },
                          icon: Icon(Icons.translate)),
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
