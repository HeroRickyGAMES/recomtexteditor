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
    _sanitizeCustomSequences();
    _extractStrings();
    _extractPointers();
  }

  final Map<String, List<int>> replacementToBytes = {
    'o=': [0x99, 0xAA],
    'i=': [0x99, 0xA5],
    'U=': [0x99, 0x96],
    'a=': [0x99, 0x9B],
    'E=': [0x99, 0x87],
    'e=': [0x99, 0xA1],
    'i[': [0x99, 0xA7],
    'a[': [0x99, 0xA7],
    'A[': [0x99, 0xC4],
    '----': [0x81, 0x5C, 0x81, 0xF4],
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
        result.addAll(latin1.encode(text[i]));
        i++;
      }
    }

    result.add(0); // null terminator
    return result;
  }

  //Aqui é aonde fica as conversões que o conversor não consegue ler na tradução
  void _sanitizeCustomSequences() {
    final pattern = [0x81, 0x5C, 0x81, 0xF4];
    final replacement = latin1.encode('----');

    final patternEsIon = [0x99, 0xAA];
    final replacemento = latin1.encode('o=');

    final patternEsI = [0x99, 0xA5];
    final replacementi = latin1.encode('i=');

    final patternEsU = [0x99, 0x96];
    final replacementU = latin1.encode('U=');

    final patternEsa = [0x99, 0x9B];
    final replacementa = latin1.encode('a=');

    final patternEsE = [0x99, 0x87];
    final replacementE = latin1.encode('E=');

    final patternEse = [0x99, 0xA1];
    final replacemente = latin1.encode('e=');

    final patternEsidoispontosEmCima = [0x99, 0xA7];
    final replacementEsidoispontosEmCima = latin1.encode('i[');

    final patternatil = [0x99, 0xE3];
    final replacementatil = latin1.encode('a[');

    final patternAtil = [0x99, 0xC4];
    final replacementAtil = latin1.encode('A[');

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
        if (i + 1 < data.length &&
            data[i] == patternEsIon[0] &&
            data[i + 1] == patternEsIon[1]) {
          sanitized.addAll(replacemento);
          i += 2;
        }else{
          if (i + 1 < data.length &&
              data[i] == patternEsI[0] &&
              data[i + 1] == patternEsI[1]) {
            sanitized.addAll(replacementi);
            i += 2;
          }else{
            if (i + 1 < data.length &&
                data[i] == patternEsU[0] &&
                data[i + 1] == patternEsU[1]) {
              sanitized.addAll(replacementU);
              i += 2;
            }else{
              if (i + 1 < data.length &&
                  data[i] == patternEsa[0] &&
                  data[i + 1] == patternEsa[1]) {
                sanitized.addAll(replacementa);
                i += 2;
              }else{
                if (i + 1 < data.length &&
                    data[i] == patternEsE[0] &&
                    data[i + 1] == patternEsE[1]) {
                  sanitized.addAll(replacementE);
                  i += 2;
                }else{
                  if (i + 1 < data.length &&
                      data[i] == patternEse[0] &&
                      data[i + 1] == patternEse[1]) {
                    sanitized.addAll(replacemente);
                    i += 2;
                  }else{
                    if (i + 1 < data.length &&
                        data[i] == patternEsidoispontosEmCima[0] &&
                        data[i + 1] == patternEsidoispontosEmCima[1]) {
                      sanitized.addAll(replacementEsidoispontosEmCima);
                      i += 2;
                    }else{
                      if (i + 1 < data.length &&
                          data[i] == patternatil[0] &&
                          data[i + 1] == patternatil[1]) {
                        sanitized.addAll(replacementatil);
                        i += 2;
                      }else{
                        if (i + 1 < data.length &&
                            data[i] == patternAtil[0] &&
                            data[i + 1] == patternatil[1]) {
                          sanitized.addAll(replacementAtil);
                          i += 2;
                        }else{
                          sanitized.add(data[i]);
                          i++;
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    data = Uint8List.fromList(sanitized);

    // ... outras definições de padrões e substituições ...

    for (int i = 0; i < data.length;) {
      bool shouldSkip = false;

      // Verificar se o byte corrente é um ponteiro para caracteres "estranhos"
      if (pointers.containsKey(i)) {
        int pointerValue = pointers[i]!;
        if (strings.containsKey(pointerValue)) {
          String targetString = strings[pointerValue]!;

          // Se a string no ponteiro contiver um caractere não desejado, substituir
          if (targetString.contains('----')) {
            sanitized.addAll(replacement);
            i += 4;  // Avançar os bytes do ponteiro
            shouldSkip = true;
          }
        }
      }

      // Se não for um ponteiro, aplicar sanitização normal
      if (!shouldSkip) {
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
    }

    data = Uint8List.fromList(sanitized);
  }

  void _extractStrings() {
    strings.clear();
    for (int i = 0; i < data.length; i++) {
      if (data[i] >= 32 && data[i] <= 126 || data[i] >= 160) {
        final start = i;
        while (i < data.length && data[i] != 0) i++;
        final strBytes = data.sublist(start, i);
        if (strBytes.isEmpty) continue;

        String extractedString = latin1.decode(strBytes);

        // Filtro de padrões suspeitos
        if (extractedString.contains("@CTD") ||
            extractedString.contains('ÿ') ||
            extractedString.contains('à') ||
            extractedString.contains('') ||
            extractedString.contains('@') ||
            extractedString.contains('¨') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('MVS') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('§') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('') ||
            extractedString.contains('¬') ||
            extractedString.contains('>	') ||
            extractedString.contains('!	') ||
            extractedString.contains('®') ||
            extractedString.contains('¤')
        ) {
          print("Exceção encontrada");
          continue;
        }

        // Filtro de strings muito curtas
        if (extractedString.length <= 2) continue;

        print(extractedString.length);
        print("String extraída: $extractedString");

        // Armazena a string se passou nos filtros
        strings[start] = extractedString;
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

    Uint8List newStringBytes = Uint8List.fromList(latin1.encode(newText) + [0]);
    String oldText = strings[oldOffset]!;
    int oldLength = latin1.encode(oldText).length + 1; // real length in bytes
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