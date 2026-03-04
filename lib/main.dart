import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:translator_plus/translator_plus.dart';
import 'kh1_exchange.dart';

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
      
      //CARACTERES DESCONHECIDOS!
      'ô': [0xDA, 0xDA],
      'Ô': [0xDA, 0xDA],
      'õ': [0xDA, 0xDA],
      'Õ': [0xDA, 0xDA],
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
      home: MainMenuScreen(),
    );
  }
}

// =======================================================================
// TELA PRINCIPAL — escolha entre modos
// =======================================================================
class MainMenuScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KH HD Text Editor'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Kingdom Hearts HD Text Editor',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Programado por HeroRickyGAMES com a ajuda de Deus!',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 48),
            _MenuButton(
              icon: Icons.code,
              label: 'Modo Manual (CTD / MVS)',
              subtitle: 'Cole hexadecimal e edite strings',
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HexInputScreen()),
              ),
            ),
            const SizedBox(height: 20),
            _MenuButton(
              icon: Icons.translate,
              label: 'Traduzir Pasta KH1',
              subtitle: 'Abre pasta hed_out e traduz UK→PT-BR (exchange files)',
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ExchangeTranslateScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.15),
          side: BorderSide(color: color, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          alignment: Alignment.centerLeft,
        ),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
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

// =======================================================================
// TELA DE TRADUÇÃO — PASTA KH1 EXCHANGE
// =======================================================================
class _SearchHit {
  final ExchangeFile file;
  final int idx;
  final String text;
  _SearchHit({required this.file, required this.idx, required this.text});
}

class ExchangeTranslateScreen extends StatefulWidget {
  @override
  _ExchangeTranslateScreenState createState() =>
      _ExchangeTranslateScreenState();
}

class _ExchangeTranslateScreenState extends State<ExchangeTranslateScreen> {
  final TextEditingController _hedPathCtrl = TextEditingController();
  final TextEditingController _outPathCtrl = TextEditingController(
    text: '/run/media/heroricky/JOGOS/khtraduzido',
  );

  List<ExchangeFile> _files = [];
  ExchangeFile? _selectedFile;
  int? _selectedStringIdx;
  final TextEditingController _editCtrl = TextEditingController();

  bool _isTranslating = false;
  bool _isLoading = false;
  int _progress = 0;
  int _total = 0;
  String _status = '';
  String _lastResult = '';

  KH1BatchTranslator? _translator;

  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Listener para atualizar contador de chars quando usuário digita
    _editCtrl.addListener(_onEditTextChanged);
  }

  void _onEditTextChanged() => setState(() {});

  @override
  void dispose() {
    _editCtrl.removeListener(_onEditTextChanged);
    _searchCtrl.dispose();
    _editCtrl.dispose();
    _hedPathCtrl.dispose();
    _outPathCtrl.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Pesquisa global em todos os arquivos carregados
  // -----------------------------------------------------------------------
  static final _ctrlRegex = RegExp(r'\[(?:C|BTN|\?):[0-9A-Fa-f]{2,4}\]');

  // Limpa códigos de controle para comparação de texto puro
  static String _cleanForSearch(String raw) {
    return raw
        .replaceAll(_ctrlRegex, ' ') // [C:0C] → espaço (não remove, substitui!)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<_SearchHit> get _searchResults {
    if (_searchQuery.trim().isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    final out = <_SearchHit>[];
    for (final ef in _files) {
      for (int i = 0; i < ef.strings.length; i++) {
        final raw = ef.strings[i];
        final clean = _cleanForSearch(raw);
        if (clean.toLowerCase().contains(q)) {
          out.add(_SearchHit(file: ef, idx: i, text: raw));
        }
      }
    }
    return out;
  }

  Widget _buildSearchResults() {
    final results = _searchResults;
    if (results.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma string contém "$_searchQuery".',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '${results.length} resultado(s) para "$_searchQuery"',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[800]),
            itemBuilder: (_, i) {
              final hit = results[i];
              final fileName =
                  hit.file.ukDataPath.split('/').last.replaceFirst('UK_', '');
              final isSelected =
                  _selectedFile == hit.file && _selectedStringIdx == hit.idx;
              return ListTile(
                dense: true,
                selected: isSelected,
                selectedTileColor: Colors.blue.withOpacity(0.2),
                title: Row(
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blueAccent,
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '[${hit.idx.toString().padLeft(3, '0')}]',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
                subtitle: Text(
                  hit.text.isEmpty
                      ? '(vazio)'
                      : _cleanForSearch(hit.text),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => setState(() {
                  _selectedFile = hit.file;
                  _selectedStringIdx = hit.idx;
                  _editCtrl.text = hit.text;
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Seleciona pasta hed_out
  // -----------------------------------------------------------------------
  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecione a pasta kh1_NOME.hed_out',
    );
    if (result != null) {
      setState(() {
        _hedPathCtrl.text = result;
        _files = [];
        _selectedFile = null;
      });
    }
  }

  // -----------------------------------------------------------------------
  // Escaneia e carrega arquivos exchange
  // Aceita tanto uma pasta raiz (kh1_mods) quanto uma hed_out específica
  // -----------------------------------------------------------------------
  Future<void> _scanFiles() async {
    final inputPath = _hedPathCtrl.text.trim();
    if (inputPath.isEmpty) return;

    setState(() {
      _isLoading = true;
      _status = 'Escaneando...';
      _files = [];
    });

    // Yield ao event loop para UI atualizar (mostra loading antes do I/O)
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final outPath = _outPathCtrl.text.trim();

      // Decide se é pasta raiz ou uma hed_out direta
      List<String> hedPaths;
      final lastName = inputPath.split('/').last;
      if (lastName.endsWith('.hed_out')) {
        hedPaths = [inputPath];
      } else {
        hedPaths = KH1BatchTranslator.discoverHedOutFolders(inputPath);
        if (hedPaths.isEmpty) hedPaths = [inputPath]; // fallback
      }

      final List<ExchangeFile> allFiles = [];
      for (int hi = 0; hi < hedPaths.length; hi++) {
        final hedPath = hedPaths[hi];
        setState(() {
          _status = 'Escaneando pacote ${hi + 1}/${hedPaths.length}...\n${hedPath.split('/').last}';
        });
        await Future.delayed(const Duration(milliseconds: 16)); // yield UI
        final t = KH1BatchTranslator(hedOutPath: hedPath, outputBase: outPath);
        final found = t.scanFiles();
        for (final ef in found) {
          ef.load();
        }
        allFiles.addAll(found);
      }

      if (allFiles.isEmpty) {
        setState(() {
          _isLoading = false;
          _status = 'Nenhum arquivo UK_ encontrado!\n'
              'Selecione a pasta raiz "kh1_mods" ou uma pasta "kh1_xxx.hed_out".\n'
              'Pasta usada: $inputPath';
        });
        return;
      }

      setState(() {
        _files = allFiles;
        _isLoading = false;
        _status = '${allFiles.length} arquivos em ${hedPaths.length} pacote(s).';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Erro: $e';
      });
    }
  }

  // -----------------------------------------------------------------------
  // Traduz tudo automaticamente
  // -----------------------------------------------------------------------
  Future<void> _translateAll() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Traduzir Tudo (UK → PT-BR)'),
        content: const Text(
          'Isso vai traduzir todos os arquivos exchange da pasta selecionada\n'
          'do inglês para o português brasileiro.\n\n'
          'Os arquivos serão salvos byte a byte em:\n'
          'khtraduzido/kh1_NOME.hed_out/original/exchange/\n\n'
          'Termos como "Keyblade" serão preservados.\nDeseja continuar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Traduzir')),
        ],
      ),
    );
    if (confirm != true) return;

    final hedPath = _hedPathCtrl.text.trim();
    final outPath = _outPathCtrl.text.trim();
    if (hedPath.isEmpty || outPath.isEmpty) return;

    _translator = KH1BatchTranslator(
      hedOutPath: hedPath,
      outputBase: outPath,
    );

    setState(() {
      _isTranslating = true;
      _progress = 0;
      _total = 0;
      _status = 'Iniciando...';
      _lastResult = '';
    });

    _translator!.onProgress = (cur, tot, status) {
      if (mounted) {
        setState(() {
          _progress = cur;
          _total = tot;
          _status = status;
        });
      }
    };

    _translator!.onDone = (result) {
      if (mounted) {
        setState(() {
          _isTranslating = false;
          _lastResult = result;
          _status = 'Concluído!';
        });
      }
    };

    await _translator!.translateAll(_files);
  }

  void _cancelTranslation() {
    _translator?.cancelled = true;
    setState(() {
      _isTranslating = false;
      _status = 'Cancelado pelo usuário.';
    });
  }

  // -----------------------------------------------------------------------
  // Salva arquivo manualmente (edição manual)
  // -----------------------------------------------------------------------
  void _saveManual() {
    if (_selectedFile == null || _selectedStringIdx == null) return;
    final newText = _editCtrl.text;
    setState(() {
      _selectedFile!.editString(_selectedStringIdx!, newText);
    });

    // Salva byte a byte (path completo é derivado do ukDataPath do arquivo)
    try {
      _selectedFile!.save(_outPathCtrl.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Salvo byte a byte com ponteiros atualizados!'),
            duration: Duration(seconds: 2)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Traduz string individual
  // -----------------------------------------------------------------------
  Future<void> _translateSingle() async {
    final t = GoogleTranslator();
    final original = _editCtrl.text;
    final Map<String, String> prot = {};
    final toTrans = KH1Encoding.protectTerms(original, prot);
    try {
      final res = await t.translate(toTrans, from: 'en', to: 'pt');
      final restored = KH1Encoding.restoreTerms(res.text, prot);
      setState(() => _editCtrl.text = restored);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na tradução: $e')),
      );
    }
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traduzir KH1 Exchange — UK → PT-BR'),
        actions: [
          if (_isTranslating)
            Row(children: [
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 8),
              Text('$_progress/$_total — $_status',
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: _cancelTranslation,
                  child: Text('Cancelar',
                      style: TextStyle(color: Colors.red[300]))),
            ])
          else ...[
            if (_files.isNotEmpty)
              TextButton.icon(
                onPressed: _isLoading ? null : _translateAll,
                icon: const Icon(Icons.translate, color: Colors.white),
                label: const Text('Traduzir Tudo',
                    style: TextStyle(color: Colors.white)),
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          // --- Configuração de pasta ---
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _hedPathCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pasta raiz (ex: .../kh1_mods) ou hed_out específica',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                      onPressed: _pickFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Abrir')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                      onPressed: _isLoading ? null : _scanFiles,
                      icon: const Icon(Icons.search),
                      label: const Text('Escanear')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Salvar em: ',
                      style: TextStyle(color: Colors.grey)),
                  Expanded(
                    child: TextField(
                      controller: _outPathCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_status,
                      style:
                          const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                ],
                if (_isTranslating && _total > 0) ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                      value: _total > 0 ? _progress / _total : 0),
                ],
                if (_lastResult.isNotEmpty)
                  Text(_lastResult,
                      style:
                          const TextStyle(color: Colors.yellowAccent, fontSize: 12)),
              ],
            ),
          ),
          // --- Barra de pesquisa global ---
          Container(
            color: Colors.grey[850],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              enabled: _files.isNotEmpty,
              decoration: InputDecoration(
                hintText: _files.isEmpty
                    ? 'Carregue uma pasta para pesquisar...'
                    : 'Pesquisar em todos os pacotes (ex: Sliding Dash)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Limpar pesquisa',
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _searchQuery = '';
                        }),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // --- Lista de arquivos e editor ---
          Expanded(
            child: Row(
              children: [
                // Painel esquerdo: resultados de pesquisa OU lista de arquivos+strings
                if (_searchQuery.trim().isNotEmpty) ...[
                  Expanded(
                    flex: 4,
                    child: _buildSearchResults(),
                  ),
                ] else ...[
                // Lista de arquivos (esquerda)
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          '${_files.length} arquivos',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _files.length,
                          itemBuilder: (_, idx) {
                            final ef = _files[idx];
                            final name = ef.ukDataPath.split('/').last;
                            final isSelected = ef == _selectedFile;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor:
                                  Colors.blue.withOpacity(0.2),
                              title: Text(
                                name.replaceFirst('UK_', ''),
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                '${ef.strings.length} strings',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                              onTap: () => setState(() {
                                _selectedFile = ef;
                                _selectedStringIdx = null;
                                _editCtrl.clear();
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                // Lista de strings do arquivo (centro)
                if (_selectedFile != null)
                  Expanded(
                    flex: 2,
                    child: ListView.separated(
                      itemCount: _selectedFile!.strings.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey[800]),
                      itemBuilder: (_, i) {
                        final str = _selectedFile!.strings[i];
                        final isSelected = _selectedStringIdx == i;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.2),
                          title: Text(
                            '[${i.toString().padLeft(3, '0')}]',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            str.isEmpty ? '(vazio)' : str,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => setState(() {
                            _selectedStringIdx = i;
                            _editCtrl.text = str;
                          }),
                        );
                      },
                    ),
                  )
                else
                  const Expanded(
                    flex: 2,
                    child: Center(
                        child: Text('Selecione um arquivo para editar')),
                  ),
                ], // fecha else (lista de arquivos + lista de strings)
                const VerticalDivider(width: 1),
                // Editor (direita) — sempre visível
                if (_selectedStringIdx != null)
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'String [${_selectedStringIdx!.toString().padLeft(3, '0')}]  — ${_selectedFile!.ukDataPath.split('/').last}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                          if (_selectedFile!.inPlace) ...[
                            const SizedBox(height: 4),
                            Builder(builder: (ctx) {
                              final maxLen = _selectedFile!.maxStringLen(_selectedStringIdx!);
                              final curLen = _editCtrl.text.length;
                              final over = curLen > maxLen;
                              return Text(
                                'Limite in-place: $curLen / $maxLen chars${over ? " ⚠ MUITO LONGO — será truncado!" : ""}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: over ? Colors.orange : Colors.green[400],
                                  fontWeight: over ? FontWeight.bold : FontWeight.normal,
                                ),
                              );
                            }),
                          ],
                          const SizedBox(height: 8),
                          Expanded(
                            child: TextField(
                              controller: _editCtrl,
                              maxLines: null,
                              minLines: null,
                              expands: true,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                // Borda laranja quando passa do limite in-place
                                enabledBorder: (_selectedFile!.inPlace &&
                                        _editCtrl.text.length >
                                            _selectedFile!.maxStringLen(_selectedStringIdx!))
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Colors.orange, width: 2))
                                    : const OutlineInputBorder(),
                              ),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 15),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            IconButton(
                              tooltip: 'Traduzir (Google)',
                              onPressed: _translateSingle,
                              icon: const Icon(Icons.translate),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text('Salvar byte a byte'),
                              onPressed: _saveManual,
                            ),
                          ]),
                        ],
                      ),
                    ),
                  )
                else
                  const Expanded(
                    flex: 3,
                    child: Center(
                        child: Text('Selecione uma string para editar')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
