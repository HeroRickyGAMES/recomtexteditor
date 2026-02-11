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

late final Map<int, String> _byteToChar;
late final Map<String, List<int>> _charToMultiByte;
late final Map<int, String> _multiByteToChar;

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

  // Identificadores de tipo de arquivo (magic numbers)
  static const List<int> MAGIC_CTD = [0x40, 0x43, 0x54, 0x44]; // @CTD
  static const List<int> MAGIC_MVS = [0x4D, 0x56, 0x53, 0x00]; // MVS

  // Variável para armazenar o tipo de arquivo detectado
  String _fileType = "UNKNOWN";

  // Variáveis que serão preenchidas dinamicamente a partir do header.
  late int pointerTableStart;
  late int pointerTableEnd;
  late int pointerBaseAddress;

  late final Map<int, String> _byteToChar;
  late final Map<String, int> _charToByte;
  late final Map<int, String> _multiByteToChar;
  late final Map<String, List<int>> _charToMultiByte;


  HexEditor(String hexString)
      : data = Uint8List.fromList(hex.decode(hexString)) {
    _buildCharMap();
    _detectFileType(); // Detecta o tipo de arquivo antes de analisar o header
    _analyzeHeader(); // Analisa o header para encontrar os offsets dinamicamente.
    extractData();
  }

  // NOVO MÉTODO: Detecta o tipo de arquivo baseado nos magic numbers
  void _detectFileType() {
    if (data.length >= 4) {
      if (data[0] == MAGIC_CTD[0] && data[1] == MAGIC_CTD[1] && data[2] == MAGIC_CTD[2] && data[3] == MAGIC_CTD[3]) {
        _fileType = "CTD";
      } else if (data[0] == MAGIC_MVS[0] && data[1] == MAGIC_MVS[1] && data[2] == MAGIC_MVS[2] && data[3] == MAGIC_MVS[3]) {
        _fileType = "MVS";
      } else {
        _fileType = "UNKNOWN";
      }
    }
    print("Tipo de arquivo detectado: $_fileType");
  }

  /// NOVO MÉTODO INTELIGENTE: Analisa o header do arquivo para encontrar os offsets.
  void _analyzeHeader() {
    try {
      print("--- Análise do Header para tipo: $_fileType ---");

      if (_fileType == "MVS") {
        // Lógica para arquivos MVS (baseada em UK_MVS011.binl e análise)
        int numPointers = data.buffer.asByteData().getUint16(0x06, Endian.little); // Number of pointers/strings
        pointerTableStart = 0x10; // Start of the pointer table
        pointerTableEnd = pointerTableStart + (numPointers * 4); // Each pointer is 4 bytes
        pointerBaseAddress = 0; // For MVS, pointers in the table are absolute offsets from the beginning of the file.

        // Check if the calculated pointerTableEnd is within the file bounds
        if (pointerTableEnd > data.length) {
            print("AVISO: pointerTableEnd calculado para MVS excede o tamanho do arquivo. Ajustando.");
            pointerTableEnd = data.length; // Cap to file length to prevent out-of-bounds access
        }

      } else if (_fileType == "CTD") {
        // Lógica para arquivos CTD: Ponteiros relativos
        pointerTableStart = data.buffer.asByteData().getUint32(0x08, Endian.little); // Início da tabela de ponteiros
        pointerBaseAddress = data.buffer.asByteData().getUint32(0x0C, Endian.little); // Endereço base para ponteiros relativos (e fim da tabela de ponteiros)
        pointerTableEnd = pointerBaseAddress; // A tabela de ponteiros termina no endereço base das strings

        // Adiciona uma verificação para os limites do arquivo
        if (pointerTableEnd > data.length || pointerTableStart >= pointerTableEnd) {
          print("ERRO: Offsets CTD calculados inválidos (${pointerTableStart.toRadixString(16)}, ${pointerTableEnd.toRadixString(16)}, ${pointerBaseAddress.toRadixString(16)}). Usando valores de fallback.");
          // Valores de fallback se os offsets calculados forem inválidos
          pointerTableStart = 0x194;
          pointerTableEnd = 0x0A74;
          pointerBaseAddress = 0x0A70; // Fallback para ponteiros relativos
        }

      } else {
        // Fallback para tipo UNKNOWN ou se os magic numbers não corresponderem
        print("Tipo de arquivo UNKNOWN ou magic numbers não correspondem. Usando valores de fallback.");
        pointerTableStart = 0x194; // Fallback value
        pointerTableEnd = 0x0A74; // Fallback value
        pointerBaseAddress = 0x0A70; // Fallback value
      }

      print("Tabela de Ponteiros Inicia em: 0x${pointerTableStart.toRadixString(16).toUpperCase()}");
      print("Tabela de Ponteiros Termina em: 0x${pointerTableEnd.toRadixString(16).toUpperCase()}");
      print("Base dos Ponteiros: 0x${pointerBaseAddress.toRadixString(16).toUpperCase()}");
      print("--------------------------");

    } catch (e) {
      print("Erro ao analisar o header para o tipo $_fileType. Usando valores de fallback. Erro: $e");
      // Fallback genérico em caso de erro na leitura do header
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

    // Mapa de caracteres de 1 byte para facilitar a busca no encode
    _charToByte = {for (var e in _byteToChar.entries) e.value: e.key};

    // Tabela customizada para caracteres de 2 bytes
    _charToMultiByte = {
      'ç': [0x99, 0x9F],
      'ã': [0x99, 0x9D],
      'â': [0x99, 0x9C],
      'é': [0x99, 0xA1],
      'ê': [0x99, 0xA2],
      'í': [0x99, 0xA5],
      'ó': [0x99, 0xAA],
      'á': [0x99, 0x9B],
      'ú': [0x99, 0x96],
      'ï': [0x99, 0xA7],
      'Ó': [0x99, 0x90],
      'Ç': [0x99, 0x85],
      'Ã': [0x99, 0x83],
      'ä': [0x99, 0x9E],
    };

    _multiByteToChar = {};
    _charToMultiByte.forEach((key, value) {
      final int multiByteKey = (value[0] << 8) | value[1];
      _multiByteToChar[multiByteKey] = key;
    });
  }

  String _decodeBytesToString(Uint8List bytes) {
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      int byte1 = bytes[i];

      if (i + 1 < bytes.length) {
        int byte2 = bytes[i + 1];
        int multiByteKey = (byte1 << 8) | byte2;
        if (_multiByteToChar.containsKey(multiByteKey)) {
          sb.write(_multiByteToChar[multiByteKey]);
          i++;
          continue;
        }
      }

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
    for (int i = 0; i < text.length; i++) {
      String char = text[i];

      // Check for placeholders first, as they are multi-character sequences
      if (char == '[' && (text.substring(i).startsWith("[C:") || text.substring(i).startsWith("[B:"))) {
          final endBracket = text.indexOf(']', i);
          if (endBracket != -1) {
              final placeholder = text.substring(i, endBracket + 1);
              final type = placeholder[1];
              final hexValue = placeholder.substring(3, placeholder.length - 1);

              try {
                  if (type == 'C' && hexValue.length == 4) {
                      byteList.add(int.parse(hexValue.substring(0, 2), radix: 16));
                      byteList.add(int.parse(hexValue.substring(2, 4), radix: 16));
                      i = endBracket; // Move index past the placeholder
                      continue;
                  } else if (type == 'B' && hexValue.length == 2) {
                      byteList.add(int.parse(hexValue, radix: 16));
                      i = endBracket; // Move index past the placeholder
                      continue;
                  }
              } catch (e) {
                  // Not a valid placeholder, will be treated as normal characters below.
              }
          }
      }

      // Check for multi-byte characters
      if (_charToMultiByte.containsKey(char)) {
        byteList.addAll(_charToMultiByte[char]!);
        continue;
      }

      // Handle single-byte characters
      if (_charToByte.containsKey(char)) {
        byteList.add(_charToByte[char]!);
      }
      // Unknown characters are ignored
    }
    return Uint8List.fromList(byteList);
  }

  void extractData() {
    strings.clear();
    pointers.clear();

    for (int i = pointerTableStart; i < pointerTableEnd && i <= data.length - 4; i += 4) {
      int relativeOffsetInTable = data.buffer.asByteData().getUint32(i, Endian.little);
      int absoluteStringAddress = pointerBaseAddress + relativeOffsetInTable;

      if (absoluteStringAddress < data.length) {
        pointers[i] = absoluteStringAddress;

        if (!strings.containsKey(absoluteStringAddress)) {
          int end = data.indexOf(0, absoluteStringAddress);
          if (end == -1) { end = data.length; }

          final strBytes = data.sublist(absoluteStringAddress, end);
          strings[absoluteStringAddress] = _decodeBytesToString(strBytes);
          print("Extraído (0x${absoluteStringAddress.toRadixString(16).toUpperCase()}): ${strings[absoluteStringAddress]}"); // Debug print
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
      data[offsetOfStringToEdit + newTextBytes.length] = 0x00; // Null terminator
      strings[offsetOfStringToEdit] = newText;
      return;
    }

    final Uint8List newData = Uint8List(data.length + shiftAmount);
    newData.setRange(0, offsetOfStringToEdit, data.sublist(0, offsetOfStringToEdit));
    newData.setRange(
        offsetOfStringToEdit, offsetOfStringToEdit + newTextBytes.length, newTextBytes);
    newData[offsetOfStringToEdit + newTextBytes.length] = 0x00; // Null terminator
    int originalTailStart = offsetOfStringToEdit + oldLengthInFile;
    int newTailStart = offsetOfStringToEdit + newLengthInFile;
    if (originalTailStart < data.length) {
      newData.setRange(
          newTailStart, newData.length, data.sublist(originalTailStart));
    }

    // Adjust pointers
    pointers.forEach((pointerAddress, oldAbsoluteStringAddress) {
      int newAbsoluteStringAddress = oldAbsoluteStringAddress;
      int newPointerValue = 0; // This will be the value written back to the pointer table

      if (oldAbsoluteStringAddress > offsetOfStringToEdit) { // Use > for pointers to subsequent strings only
        newAbsoluteStringAddress += shiftAmount;
      }
      
      // Calculate new pointer value based on the file type's pointerBaseAddress
      if (_fileType == "MVS") {
          newPointerValue = newAbsoluteStringAddress; // MVS pointers are absolute (pointerBaseAddress is 0)
      } else if (_fileType == "CTD") {
          newPointerValue = newAbsoluteStringAddress - pointerBaseAddress; // CTD pointers are relative to pointerBaseAddress
      } else {
          // Fallback, use the old relative calculation if file type is unknown.
          newPointerValue = newAbsoluteStringAddress - pointerBaseAddress;
      }
      
      if (pointerAddress < newData.length - 3) { // Ensure there's space for a Uint32
          newData.buffer.asByteData().setUint32(pointerAddress, newPointerValue, Endian.little);
      }
    });





    data = newData;
    // Re-analyze header and extract data as file size and offsets might have changed
    // This will rebuild the strings and pointers maps based on the new data
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
  bool _isTranslating = false;
  int _translateProgress = 0;
  int _translateTotal = 0;
  String _translateStatus = "";
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

  Future<void> _translateAll() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Traduzir Tudo com Google Tradutor"),
        content: Text(
          "Isso irá traduzir todas as legendas do inglês para o português.\n"
          "Legendas já em português serão puladas automaticamente.\n\n"
          "Deseja continuar?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Traduzir"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    List<int> pointerAddresses = editor.pointers.keys.toList();

    setState(() {
      _isTranslating = true;
      _translateProgress = 0;
      _translateTotal = pointerAddresses.length;
      _translateStatus = "Iniciando tradução...";
      selectedStringAddress = null;
    });

    int translated = 0;
    int skipped = 0;
    int errors = 0;

    for (int i = 0; i < pointerAddresses.length; i++) {
      if (!_isTranslating || !mounted) break;

      int pointerAddr = pointerAddresses[i];
      if (!editor.pointers.containsKey(pointerAddr)) {
        skipped++;
        setState(() { _translateProgress = i + 1; });
        continue;
      }

      int stringAddr = editor.pointers[pointerAddr]!;
      String originalText = editor.strings[stringAddr] ?? "";

      // Pular strings vazias ou com apenas códigos de controle
      String textForCheck = originalText
          .replaceAll(RegExp(r'\[(?:B:[0-9A-Fa-f]{2}|C:[0-9A-Fa-f]{4})\]'), '')
          .trim();
      if (textForCheck.isEmpty || textForCheck.length < 2) {
        skipped++;
        setState(() { _translateProgress = i + 1; });
        continue;
      }

      try {
        setState(() {
          _translateStatus = "Traduzindo ${i + 1}/$_translateTotal...";
          _translateProgress = i;
        });

        final translation = await translator.translate(
          originalText,
          from: 'auto',
          to: 'pt',
        );

        // Verificar se já está em português
        bool isPortuguese = false;
        try {
          String langCode = translation.sourceLanguage.code.toString().toLowerCase();
          isPortuguese = langCode.startsWith('pt');
        } catch (_) {
          // Fallback: se o texto não mudou, provavelmente já está em PT
          isPortuguese = translation.text == originalText;
        }

        if (isPortuguese) {
          skipped++;
          setState(() {
            _translateProgress = i + 1;
            _translateStatus = "Pulada (já em PT) ${i + 1}/$_translateTotal";
          });
          continue;
        }

        // Aplicar tradução e realocar ponteiros
        setState(() {
          editor.editString(stringAddr, translation.text);
          _translateProgress = i + 1;
        });

        translated++;

        // Delay para evitar rate limiting do Google
        await Future.delayed(Duration(milliseconds: 200));
      } catch (e) {
        print("Erro ao traduzir string em 0x${stringAddr.toRadixString(16)}: $e");
        errors++;
        setState(() { _translateProgress = i + 1; });
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    setState(() {
      _isTranslating = false;
      _translateStatus = "";
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Tradução Completa!"),
          content: Text(
            "Traduzidas: $translated\n"
            "Puladas: $skipped\n"
            "Erros: $errors",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("OK"),
            ),
          ],
        ),
      );
    }
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
          if (_isTranslating)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    _translateStatus,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _isTranslating = false),
                    child: Text("Cancelar", style: TextStyle(color: Colors.red[300])),
                  ),
                ],
              ),
            )
          else
            TextButton.icon(
              onPressed: _translateAll,
              icon: Icon(Icons.translate, color: Colors.white),
              label: Text("Traduzir Tudo", style: TextStyle(color: Colors.white)),
            ),
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
