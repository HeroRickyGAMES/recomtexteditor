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

  void debugPointers() {
    print('\n=== DEBUG DOS PONTEIROS ===');
    pointers.forEach((offset, pointerValue) {
      String str;
      try {
        str = _readStringAtOffset(pointerValue);
      } catch (_) {
        str = '[ERRO AO LER STRING]';
      }

      print('0x${offset.toRadixString(16)} → 0x${pointerValue.toRadixString(16)}: "$str"');
    });
  }


  List<int> encodeWithCustomBytes(String text) {
    List<int> result = [];
    int i = 0;

    while (i < text.length) {
      result.add(text.codeUnitAt(i)); // ISO 8859-1 / ASCII compatível
      i++;
    }

    result.addAll(latin1.encode(text)); // codifica corretamente com acentos
    result.add(0); // null terminator
    return result;
  }

  //Aqui é aonde fica as conversões que o conversor não consegue ler na tradução
  void _sanitizeCustomSequences() {
    final newData = <int>[];
    int i = 0;
    while (i < data.length) {
      newData.add(data[i]);
      i++;
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

    final result = StringBuffer();
    int i = 0;

    while (i < bytes.length) {
      result.writeCharCode(bytes[i]);
      i++;
    }

    return result.toString();
  }


  void _extractStrings() {
    strings.clear();
    for (int i = 0; i < data.length; i++) {
      if (data[i] >= 0x20 && data[i] <= 0x7E) { // ASCII visível
        int start = i;
        while (i < data.length && data[i] >= 0x20 && data[i] <= 0x7E) {
          i++;
        }
        String str = latin1.decode(data.sublist(start, i));
        strings[start] = str;
        print('[$start] → "$str"'); // <-- Adiciona isso aqui!
      }
    }
  }

  void replaceStringAtOffset(int offset, String newText) {
    // Apaga a string antiga (até o próximo 0x00)
    int i = offset;
    while (i < data.length && data[i] != 0) {
      data[i] = 0x00;
      i++;
    }

    // Escreve a nova string codificada
    final encoded = latin1.encode(newText);
    for (int j = 0; j < encoded.length; j++) {
      if (offset + j < data.length) {
        data[offset + j] = encoded[j];
      }
    }

    // Adiciona o terminador nulo no fim
    if (offset + encoded.length < data.length) {
      data[offset + encoded.length] = 0x00;
    }
  }


  void _extractPointers() {
    pointers.clear();

    // Armazena ponteiros válidos temporariamente
    final tempPointers = <int, int>{};

    for (int i = 0; i <= data.length - 4; i += 4) {
      int possiblePointer = data.buffer.asByteData().getUint32(i, Endian.little);

      if (possiblePointer > 0 &&
          possiblePointer < data.length &&
          data[possiblePointer] != 0) {
        try {
          String str = _readStringAtOffset(possiblePointer);
          if (str.isNotEmpty) {
            tempPointers[i] = possiblePointer;
          }
        } catch (_) {
          // Ignora ponteiros inválidos
        }
      }
    }

    // Reorganiza os ponteiros colocando o que aponta para "Kingdom Key" primeiro
    var sortedEntries = tempPointers.entries.toList();

    sortedEntries.sort((a, b) {
      String aStr = _readStringAtOffset(a.value);
      String bStr = _readStringAtOffset(b.value);

      if (aStr == "Kingdom Key") return -1;
      if (bStr == "Kingdom Key") return 1;
      return 0; // mantém a ordem
    });

    // Copia para o mapa final
    for (var entry in sortedEntries) {
      pointers[entry.key] = entry.value;
    }
  }

  void editString(int oldOffset, String newText) {
    print('ANTES DA EDIÇÃO:');
    debugPointers();
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

    print('DEPOIS DA EDIÇÃO:');
    debugPointers();
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
                  Row(
                    children: [
                      IconButton(onPressed: () async {
                        textController.text = await TradutorClass(textController.text);
                        setState(() {

                        });
                      }, icon: Icon(Icons.translate)),
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