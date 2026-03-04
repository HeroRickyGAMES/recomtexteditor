// kh1_exchange.dart
// Lógica de encoding/decoding e leitura/escrita dos arquivos exchange do KH1 HD
// Programado por HeroRickyGAMES com a ajuda de Deus!

import 'dart:io';
import 'dart:typed_data';
import 'package:translator_plus/translator_plus.dart';

// =============================================================================
// ENCODING KH1 EUROPEU
// Tabela:
//   0x00        → fim de string
//   0x01        → espaço ' '
//   0x02        → fim de string alternativo / quebra de linha
//   0x03-0x1F   → códigos de controle [C:XX]
//   0x2B-0x44   → maiúsculas A-Z   (char = byte + 0x16)
//   0x45-0x5E   → minúsculas a-z   (char = byte + 0x1C)
//   0x5F        → !
//   0x60        → ?
//   0x61        → ¥
//   0x62        → %
//   0x63        → +
//   0x64        → -
//   0x65        → ¢
//   0x66        → /
//   0x67        → ※
//   0x68        → .
//   0x69        → ,
//   0x6A        → ·
//   0x6B        → :
//   0x6C        → ;
//   0x6D        → …
//   0x6E-0x6F   → - (hífen)
//   0x70-0xBF   → ícones de botão [BTN:XX]
//   0xC0-0xFF   → Latin-1 direto (é, ñ, á, ã, ç, etc.)
// =============================================================================
class KH1Encoding {
  static const Map<int, String> _punctMap = {
    0x5F: '!',
    0x60: '?',
    0x61: '¥',
    0x62: '%',
    0x63: '+',
    0x64: '-',
    0x65: '¢',
    0x66: '/',
    0x67: '※',
    0x68: '.',
    0x69: ',',
    0x6A: '·',
    0x6B: ':',
    0x6C: ';',
    0x6D: '…',
    0x6E: '-',
    0x6F: '-',
  };

  static const Map<String, int> _punctReverseMap = {
    '!': 0x5F,
    '?': 0x60,
    '¥': 0x61,
    '%': 0x62,
    '+': 0x63,
    '-': 0x64,
    '¢': 0x65,
    '/': 0x66,
    '※': 0x67,
    '.': 0x68,
    ',': 0x69,
    '·': 0x6A,
    ':': 0x6B,
    ';': 0x6C,
    '…': 0x6D,
  };

  // Termos que NÃO devem ser traduzidos
  static const List<String> _protectedTerms = [
    'Keyblade', 'Kingdom Hearts', 'Heartless', 'Nobody', 'Sora', 'Riku',
    'Kairi', 'Donald', 'Goofy', 'Mickey', 'Ansem', 'Xehanort', 'Maleficent',
    'Hollow Bastion', 'Traverse Town', 'Wonderland', 'Olympus', 'Agrabah',
    'Monstro', 'Atlantica', 'Neverland', 'End of the World', 'Destiny Islands',
    'Disney Castle', 'Deep Jungle',
  ];

  // -----------------------------------------------------------------------
  // DECODE: bytes KH1 → texto legível
  // -----------------------------------------------------------------------
  static String decode(Uint8List bytes, {int startOffset = 0}) {
    final sb = StringBuffer();
    for (int i = startOffset; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x00 || b == 0x02) break;
      if (b == 0x01) {
        sb.write(' ');
      } else if (b == 0x0A) {
        sb.write('\n');
      } else if (b >= 0x03 && b <= 0x1F) {
        sb.write('[C:${b.toRadixString(16).toUpperCase().padLeft(2, '0')}]');
      } else if (b >= 0x2B && b <= 0x44) {
        sb.write(String.fromCharCode(b + 0x16)); // maiúsculas
      } else if (b >= 0x45 && b <= 0x5E) {
        sb.write(String.fromCharCode(b + 0x1C)); // minúsculas
      } else if (_punctMap.containsKey(b)) {
        sb.write(_punctMap[b]);
      } else if (b >= 0x70 && b <= 0xBF) {
        sb.write('[BTN:${b.toRadixString(16).toUpperCase().padLeft(2, '0')}]');
      } else if (b >= 0xC0) {
        sb.write(String.fromCharCode(b)); // Latin-1 direto
      } else {
        sb.write('[?:${b.toRadixString(16).toUpperCase().padLeft(2, '0')}]');
      }
    }
    return sb.toString();
  }

  // -----------------------------------------------------------------------
  // ENCODE: texto legível → bytes KH1
  // -----------------------------------------------------------------------
  static Uint8List encode(String text) {
    final List<int> out = [];
    int i = 0;
    while (i < text.length) {
      // Placeholders [C:XX], [BTN:XX], [?:XX]
      if (text[i] == '[') {
        final end = text.indexOf(']', i);
        if (end != -1) {
          final tok = text.substring(i, end + 1);
          int? val;
          if (tok.startsWith('[C:') && tok.length == 6) {
            val = int.tryParse(tok.substring(3, 5), radix: 16);
          } else if (tok.startsWith('[BTN:') && tok.length == 9) {
            val = int.tryParse(tok.substring(5, 7), radix: 16);
          } else if (tok.startsWith('[?:') && tok.length == 7) {
            val = int.tryParse(tok.substring(3, 5), radix: 16);
          }
          if (val != null) {
            out.add(val);
            i = end + 1;
            continue;
          }
        }
      }

      final ch = text[i];
      final code = ch.codeUnitAt(0);

      if (ch == ' ') {
        out.add(0x01); // espaço KH1
      } else if (ch == '\n') {
        out.add(0x0A);
      } else if (code >= 0x41 && code <= 0x5A) {
        out.add(code - 0x16); // maiúsculas
      } else if (code >= 0x61 && code <= 0x7A) {
        out.add(code - 0x1C); // minúsculas
      } else if (_punctReverseMap.containsKey(ch)) {
        out.add(_punctReverseMap[ch]!);
      } else if (code >= 0xC0 && code <= 0xFF) {
        out.add(code); // Latin-1 direto
      }
      // Caracteres desconhecidos são ignorados silenciosamente

      i++;
    }
    return Uint8List.fromList(out);
  }

  // Remove termos protegidos antes de traduzir, restaura depois
  static String protectTerms(String text, Map<String, String> placeholders) {
    String result = text;
    int idx = 0;
    for (final term in _protectedTerms) {
      if (result.contains(term)) {
        final placeholder = '##PROT${idx}##';
        result = result.replaceAll(term, placeholder);
        placeholders[placeholder] = term;
        idx++;
      }
    }
    return result;
  }

  static String restoreTerms(String text, Map<String, String> placeholders) {
    String result = text;
    for (final entry in placeholders.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}

// =============================================================================
// EXCHANGE FILE — representa um arquivo (ou par data+offset) do exchange/
// =============================================================================
class ExchangeFile {
  final String ukDataPath;    // arquivo UK_ de origem
  final String spDataPath;    // arquivo SP_ (lido como referência de estrutura)
  final String? offsetPath;   // arquivo de offsets (16-bit), se existir
  final bool hasPair;         // true = tem _data.bin + _offset/_ofs.bin

  List<String> strings = []; // strings decodificadas do UK
  List<int> _rawOffsets = [];  // offsets originais (para reconstrução)
  Uint8List _rawData = Uint8List(0);

  ExchangeFile({
    required this.ukDataPath,
    required this.spDataPath,
    this.offsetPath,
    required this.hasPair,
  });

  // -----------------------------------------------------------------------
  // Carrega o arquivo UK como fonte de tradução
  // -----------------------------------------------------------------------
  void load() {
    strings.clear();
    _rawOffsets.clear();
    final data = File(ukDataPath).readAsBytesSync();
    _rawData = data;

    if (hasPair && offsetPath != null) {
      _loadPaired(data);
    } else {
      _loadSingle(data);
    }
  }

  void _loadPaired(Uint8List data) {
    final offData = File(offsetPath!).readAsBytesSync();
    for (int i = 0; i + 1 < offData.length; i += 2) {
      final off = offData[i] | (offData[i + 1] << 8);
      if (off < data.length) {
        _rawOffsets.add(off);
        strings.add(KH1Encoding.decode(data, startOffset: off));
      }
    }
  }

  void _loadSingle(Uint8List data) {
    // Header: primeiros 4 bytes podem ser contagem (int32 LE)
    int start = 0;
    if (data.length > 4) {
      final count = data.buffer.asByteData().getUint32(0, Endian.little);
      if (count < 300 && count > 0) start = 4; // parece um header de contagem
    }

    int pos = start;
    while (pos < data.length) {
      _rawOffsets.add(pos);
      // Encontra fim de string (0x00 ou 0x02)
      int end = pos;
      while (end < data.length && data[end] != 0x00 && data[end] != 0x02) {
        end++;
      }
      if (end > pos) {
        strings.add(KH1Encoding.decode(data.sublist(pos, end)));
      }
      pos = end + 1;
      if (pos >= data.length) break;
    }
  }

  // -----------------------------------------------------------------------
  // Edita uma string por índice — mantém lógica de ajuste de ponteiros
  // -----------------------------------------------------------------------
  void editString(int index, String newText) {
    if (index < 0 || index >= strings.length) return;
    strings[index] = newText;
  }

  // -----------------------------------------------------------------------
  // Serializa e salva byte a byte no caminho SP de destino
  // -----------------------------------------------------------------------
  void save(String outputBase) {
    final spFileName = _spFilename(ukDataPath);
    final relPath = _relativePathFromExchange(spDataPath);
    final outDir = Directory('$outputBase/$relPath');
    outDir.createSync(recursive: true);

    if (hasPair && offsetPath != null) {
      _savePaired(outDir.path, spFileName);
    } else {
      _saveSingle(outDir.path, spFileName);
    }
  }

  void _savePaired(String outDirPath, String spFileName) {
    // Reconstrói data buffer com ajuste de ponteiros
    final List<int> newData = [];
    final List<int> newOffsets = [];

    for (final str in strings) {
      newOffsets.add(newData.length);
      final encoded = KH1Encoding.encode(str);
      newData.addAll(encoded);
      newData.add(0x00); // null terminator
    }

    // Escreve _data.bin byte a byte
    final dataOut = File('$outDirPath/$spFileName');
    dataOut.writeAsBytesSync(Uint8List.fromList(newData));

    // Escreve _offset.bin ou _ofs.bin byte a byte (16-bit LE)
    final spOffsetName = _spFilename(offsetPath!);
    final List<int> offsetBytes = [];
    for (final off in newOffsets) {
      offsetBytes.add(off & 0xFF);
      offsetBytes.add((off >> 8) & 0xFF);
    }
    // Padding com 0xCD para manter tamanho original se necessário
    final origOffSize = File(offsetPath!).lengthSync();
    while (offsetBytes.length < origOffSize) {
      offsetBytes.add(0xCD);
    }
    final offOut = File('$outDirPath/$spOffsetName');
    offOut.writeAsBytesSync(Uint8List.fromList(offsetBytes));
  }

  void _saveSingle(String outDirPath, String spFileName) {
    // Mantém header original (4 bytes de contagem se existia)
    final List<int> newData = [];
    if (_rawData.length > 4) {
      final count = _rawData.buffer.asByteData().getUint32(0, Endian.little);
      if (count < 300 && count > 0) {
        newData.addAll(_rawData.sublist(0, 4)); // mantém header
      }
    }

    for (final str in strings) {
      final encoded = KH1Encoding.encode(str);
      newData.addAll(encoded);
      newData.add(0x02); // terminador alternativo
    }

    final out = File('$outDirPath/$spFileName');
    out.writeAsBytesSync(Uint8List.fromList(newData));
  }

  // Helpers
  static String _spFilename(String ukPath) {
    final name = ukPath.split('/').last;
    if (name.startsWith('UK_')) return 'SP_${name.substring(3)}';
    return name;
  }

  static String _relativePathFromExchange(String fullPath) {
    // Retorna "kh1_first.hed_out/original/exchange" (ou .../menu/sp, etc.)
    // incluindo o nome do hed_out até o diretório pai do arquivo
    final parts = fullPath.split('/');
    final hedIdx = parts.indexWhere((p) => p.endsWith('.hed_out'));
    if (hedIdx == -1) return 'exchange';
    return parts.sublist(hedIdx, parts.length - 1).join('/');
  }
}

// =============================================================================
// BATCH TRANSLATOR — escaneia pasta exchange e traduz todos os UK_ → SP_ PT-BR
// =============================================================================
class KH1BatchTranslator {
  final String hedOutPath;   // ex: /run/media/.../kh1_first.hed_out
  final String outputBase;   // ex: /run/media/.../khtraduzido
  final GoogleTranslator _translator = GoogleTranslator();

  // Callbacks de progresso
  Function(int current, int total, String status)? onProgress;
  Function(String result)? onDone;
  bool cancelled = false;

  KH1BatchTranslator({required this.hedOutPath, required this.outputBase});

  // -----------------------------------------------------------------------
  // Descobre todos os kh1_*.hed_out dentro de uma pasta raiz
  // -----------------------------------------------------------------------
  static List<String> discoverHedOutFolders(String rootPath) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return [];
    final found = dir
        .listSync()
        .whereType<Directory>()
        .where((d) {
          final name = d.path.split('/').last;
          return name.startsWith('kh1_') && name.endsWith('.hed_out');
        })
        .map((d) => d.path)
        .toList();
    found.sort();
    return found;
  }

  // -----------------------------------------------------------------------
  // Escaneia pasta exchange e monta lista de ExchangeFile
  // -----------------------------------------------------------------------
  List<ExchangeFile> scanFiles() {
    final exchangeDir = Directory('$hedOutPath/original/exchange');
    if (!exchangeDir.existsSync()) return [];

    final files = exchangeDir.listSync().whereType<File>().toList();
    final List<ExchangeFile> result = [];
    final Set<String> handled = {};

    for (final f in files) {
      final name = f.path.split('/').last;
      if (!name.startsWith('UK_')) continue;
      if (handled.contains(name)) continue;

      // Verifica se tem par de offsets
      final baseName = name.replaceFirst('UK_', '');
      final dataName = baseName.replaceAll(RegExp(r'\.bin$'), '_data.bin');
      final ofsName1 = baseName.replaceAll(RegExp(r'\.bin$'), '_offset.bin');
      final ofsName2 = baseName.replaceAll(RegExp(r'\.bin$'), '_ofs.bin');

      String? offsetPath;
      bool hasPair = false;

      // Verifica se o próprio arquivo É o _data.bin (ex: UK_wsysmsg_data.bin)
      if (name.contains('_data.bin')) {
        // Procura o _offset.bin ou _ofs.bin correspondente
        final stem = name.replaceFirst('UK_', '').replaceAll('_data.bin', '');
        final offFile1 = '${exchangeDir.path}/UK_${stem}_offset.bin';
        final offFile2 = '${exchangeDir.path}/UK_${stem}_ofs.bin';
        if (File(offFile1).existsSync()) {
          offsetPath = offFile1;
          hasPair = true;
        } else if (File(offFile2).existsSync()) {
          offsetPath = offFile2;
          hasPair = true;
        }
      }

      final spPath = '${exchangeDir.path}/SP_${name.replaceFirst('UK_', '')}';

      final ef = ExchangeFile(
        ukDataPath: f.path,
        spDataPath: spPath,
        offsetPath: offsetPath,
        hasPair: hasPair,
      );

      // Inclui mesmo sem SP_ pré-existente (será criado no save)
      result.add(ef);
      handled.add(name);
    }

    return result;
  }

  // -----------------------------------------------------------------------
  // Traduz todos os arquivos
  // -----------------------------------------------------------------------
  Future<void> translateAll(List<ExchangeFile> files) async {
    int totalStrings = 0;
    int doneStrings = 0;
    int translated = 0;
    int skipped = 0;
    int errors = 0;

    // Carrega todos e conta strings
    for (final ef in files) {
      try {
        ef.load();
        totalStrings += ef.strings.length;
      } catch (e) {
        // Arquivo problemático, ignora
      }
    }

    onProgress?.call(0, totalStrings, 'Iniciando...');

    for (final ef in files) {
      if (cancelled) break;
      final fileName = ef.ukDataPath.split('/').last;

      for (int i = 0; i < ef.strings.length; i++) {
        if (cancelled) break;

        final original = ef.strings[i];
        // Filtra strings sem texto real
        final clean = original
            .replaceAll(RegExp(r'\[(?:C|BTN|\?):[\dA-Fa-f]{2}\]'), '')
            .trim();
        if (clean.length < 2) {
          skipped++;
          doneStrings++;
          onProgress?.call(doneStrings, totalStrings,
              '$fileName [$i/${ef.strings.length}]');
          continue;
        }

        try {
          // Protege termos
          final Map<String, String> prot = {};
          final toTranslate = KH1Encoding.protectTerms(original, prot);

          final translation = await _translator.translate(
            toTranslate,
            from: 'en',
            to: 'pt',
          );

          String translatedText = translation.text;

          // Ignora se já estava em PT
          bool alreadyPt = false;
          try {
            alreadyPt = translation.sourceLanguage.code
                .toLowerCase()
                .startsWith('pt');
          } catch (_) {
            alreadyPt = translatedText == toTranslate;
          }

          if (alreadyPt) {
            skipped++;
          } else {
            translatedText = KH1Encoding.restoreTerms(translatedText, prot);
            ef.editString(i, translatedText);
            translated++;
          }

          await Future.delayed(const Duration(milliseconds: 150));
        } catch (e) {
          errors++;
          await Future.delayed(const Duration(milliseconds: 500));
        }

        doneStrings++;
        onProgress?.call(doneStrings, totalStrings,
            '$fileName [$i/${ef.strings.length}]');
      }

      // Salva cada arquivo ao terminar (o path completo vem de _relativePathFromExchange)
      if (!cancelled) {
        try {
          ef.save(outputBase);
        } catch (e) {
          errors++;
        }
      }
    }

    onDone?.call(
        'Traduzidas: $translated | Puladas: $skipped | Erros: $errors');
  }
}
