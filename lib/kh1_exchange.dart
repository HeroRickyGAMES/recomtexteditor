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
//   0xC0-0xFF   → NÃO é Latin-1 direto! Mapeamento real confirmado via US_font_data_tbl.bin:
//               Maiúsculas: Á=0xCD, Â=0xCE, Ä=0xCF, Ç=0xD0, É=0xD2, Ê=0xD3,
//                           Í=0xD6, Ó=0xDB, Ô=0xDC, Ö=0xDD, Ù=0xDE, Ú=0xDF,
//                           Û=0xE0, Ü=0xE1
//               Minúsculas: à=0xE3, á=0xE4, â=0xE5, ä=0xE6, ç=0xE7, è=0xE8,
//                           é=0xE9, ê=0xEA, ë=0xEB, ì=0xEC, í=0xED, î=0xEE,
//                           ï=0xEF, ñ=0xF0, ò=0xF1, ó=0xF2, ô=0xF3, ö=0xF4,
//                           ù=0xF5, ú=0xF6, û=0xF7, ü=0xF8
//               PT-BR (ã/õ não existem na fonte — substituídos por ä/ö):
//                           ã→ä(0xE6), Ã→Ä(0xCF), õ→ö(0xF4), Õ→Ö(0xDD)
// =============================================================================
class KH1Encoding {
  static const Map<int, String> _punctMap = {
    // Pontuação (0x5F-0x6F)
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

  // Mapeamento CORRETO de caracteres acentuados → bytes KH1
  // Confirmado via US_font_data_tbl.bin (560 entradas × 16 bytes)
  // PT-BR: ã/õ não existem na fonte → substituídos por ä/ö (dois pontos)
  static const Map<String, int> _accentEncode = {
    // Maiúsculas
    'Á': 0xCD, 'Â': 0xCE, 'Ä': 0xCF, 'Ç': 0xD0,
    'É': 0xD2, 'Ê': 0xD3, 'Í': 0xD6,
    'Ó': 0xDB, 'Ô': 0xDC, 'Ö': 0xDD,
    'Ù': 0xDE, 'Ú': 0xDF, 'Û': 0xE0, 'Ü': 0xE1,
    // Minúsculas
    'à': 0xE3, 'á': 0xE4, 'â': 0xE5, 'ä': 0xE6, 'ç': 0xE7,
    'è': 0xE8, 'é': 0xE9, 'ê': 0xEA, 'ë': 0xEB,
    'ì': 0xEC, 'í': 0xED, 'î': 0xEE, 'ï': 0xEF,
    'ñ': 0xF0, 'ò': 0xF1, 'ó': 0xF2, 'ô': 0xF3, 'ö': 0xF4,
    'ù': 0xF5, 'ú': 0xF6, 'û': 0xF7, 'ü': 0xF8,
    // PT-BR: ã→ä(0xE6), Ã→Ä(0xCF), õ→ö(0xF4), Õ→Ö(0xDD)
    'ã': 0xE6, 'Ã': 0xCF,
    'õ': 0xF4, 'Õ': 0xDD,
  };

  // Mapeamento CORRETO de bytes KH1 → caracteres (para decode/exibição)
  static const Map<int, String> _accentDecode = {
    // Maiúsculas
    0xCD: 'Á', 0xCE: 'Â', 0xCF: 'Ä', 0xD0: 'Ç',
    0xD2: 'É', 0xD3: 'Ê', 0xD6: 'Í',
    0xDB: 'Ó', 0xDC: 'Ô', 0xDD: 'Ö',
    0xDE: 'Ù', 0xDF: 'Ú', 0xE0: 'Û', 0xE1: 'Ü',
    // Minúsculas
    0xE3: 'à', 0xE4: 'á', 0xE5: 'â', 0xE6: 'ä', 0xE7: 'ç',
    0xE8: 'è', 0xE9: 'é', 0xEA: 'ê', 0xEB: 'ë',
    0xEC: 'ì', 0xED: 'í', 0xEE: 'î', 0xEF: 'ï',
    0xF0: 'ñ', 0xF1: 'ò', 0xF2: 'ó', 0xF3: 'ô', 0xF4: 'ö',
    0xF5: 'ù', 0xF6: 'ú', 0xF7: 'û', 0xF8: 'ü',
  };

  // Termos que NÃO devem ser traduzidos (nomes próprios do universo KH)
  static const List<String> _protectedTerms = [
    'Keyblade', 'Kingdom Hearts', 'Final Mix', 'Heartless', 'Nobody', 'Sora', 'Riku',
    'Kairi', 'Donald', 'Mickey', 'Ansem', 'Xehanort',
    'Hollow Bastion', 'Traverse Town', 'Wonderland', 'Olympus', 'Agrabah',
    'Monstro', 'Atlantica', 'Neverland', 'End of the World', 'Destiny Islands',
    'Disney Castle', 'Deep Jungle',
  ];

  // Nomes com tradução específica para PT-BR (substituídos ANTES de enviar ao Google)
  static const Map<String, String> _characterTranslations = {
    'Goofy': 'Pateta',
    'Maleficent': 'Malévola',
  };

  // -----------------------------------------------------------------------
  // DECODE: bytes KH1 → texto legível
  // -----------------------------------------------------------------------
  // breakOnEnd=true (padrão): para em 0x00 ou 0x02 (formato exchange normal)
  // breakOnEnd=false: decodifica o range inteiro sem parar (formato EvMsg, onde
  //   0x02 é separador de linha e 0x00 pode aparecer como argumento de controle)
  static String decode(Uint8List bytes, {int startOffset = 0, bool breakOnEnd = true}) {
    final sb = StringBuffer();
    for (int i = startOffset; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x00 || b == 0x02) {
        if (breakOnEnd) break;
        // EvMsg: 0x00 → [?:00], 0x02 → [C:02]
        sb.write(b == 0x00
            ? '[?:00]'
            : '[C:02]');
        continue;
      }
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
        // Mapeamento correto de bytes KH1 → caracteres (NÃO é Latin-1 direto)
        final decoded = _accentDecode[b];
        if (decoded != null) {
          sb.write(decoded);
        } else {
          sb.write('[?:${b.toRadixString(16).toUpperCase().padLeft(2, '0')}]');
        }
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
          } else if (tok.startsWith('[BTN:') && tok.length == 8) {
            val = int.tryParse(tok.substring(5, 7), radix: 16);
          } else if (tok.startsWith('[?:') && tok.length == 6) {
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
        out.add(0x02); // 0x02 = enter/quebra de linha no KH1
      } else if (code >= 0x41 && code <= 0x5A) {
        out.add(code - 0x16); // maiúsculas
      } else if (code >= 0x61 && code <= 0x7A) {
        out.add(code - 0x1C); // minúsculas
      } else if (_punctReverseMap.containsKey(ch)) {
        out.add(_punctReverseMap[ch]!);
      } else if (_accentEncode.containsKey(ch)) {
        out.add(_accentEncode[ch]!);
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

    // 1. Protege códigos de controle [C:XX] e [BTN:XX] — Google pode corrompê-los
    final codeRegex = RegExp(r'\[(?:C|BTN|\?):[\dA-Fa-f]{2}\]');
    result = result.replaceAllMapped(codeRegex, (m) {
      final ph = '##C${idx}##';
      placeholders[ph] = m.group(0)!;
      idx++;
      return ph;
    });

    // 2. Aplica traduções específicas de personagens (Goofy→Pateta, etc.)
    for (final entry in _characterTranslations.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // 3. Protege termos que NÃO devem ser traduzidos
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
  final bool inPlace;         // true = arquivo binário misto (ev), patch no lugar
  final bool isMessageV361;   // true = formato "Message v361" (sysmsg.binl) com header+tabela
  final bool isEvMsg;         // true = formato EvMsg (binl com magic "EvMsg") — rebuild, não inPlace
  final bool nullOnly;        // true = _loadSingle() divide só em 0x00 (arquivos Help com 0x02 interno)

  List<String> strings = []; // strings decodificadas (apenas não-vazias) — para a UI
  List<int> _rawOffsets = [];  // byte offsets das strings não-vazias
  Uint8List _rawData = Uint8List(0);

  // Para _saveSingle(): rastreia TODAS as posições incluindo vagas vazias
  // Necessário para preservar índice sequencial (raw index) que o game usa para buscar strings
  List<int> _rawAllPositions = [];   // offset de cada segmento (vazio ou não)
  List<bool> _rawAllIsEmpty = [];    // true = segmento vazio (só \0)

  // Para _saveMessageV361(): sufixo de cada slot (do primeiro terminador até o fim do slot)
  // Inclui o byte terminador (0x00/0x02) e quaisquer bytes adicionais de formatação
  List<Uint8List> _rawSuffixes = [];
  // Bytes de padding após o último slot (dat_size pode ser > sentinel value)
  Uint8List _rawMsgTrailing = Uint8List(0);

  // Para _loadEvMsg()/_saveEvMsg(): regiões de texto dentro do arquivo EvMsg
  // Paralelas entre si; _evmsgAllStringIdx[i] = índice em strings[] ou -1 (entrada sem texto real)
  List<int> _evmsgAllTextStarts = []; // posição onde o texto começa (após 07 0C 00)
  List<int> _evmsgAllTextEnds = [];   // posição do byte 05 (fim exclusivo do texto)
  List<int> _evmsgAllStringIdx = [];  // índice em strings[], ou -1 se não é texto real

  ExchangeFile({
    required this.ukDataPath,
    required this.spDataPath,
    this.offsetPath,
    required this.hasPair,
    this.inPlace = false,
    this.isMessageV361 = false,
    this.isEvMsg = false,
    this.nullOnly = false,
  });

  // -----------------------------------------------------------------------
  // Carrega o arquivo UK como fonte de tradução
  // -----------------------------------------------------------------------
  void load() {
    strings.clear();
    _rawOffsets.clear();
    _rawAllPositions.clear();
    _rawAllIsEmpty.clear();
    _rawSuffixes.clear();
    _rawMsgTrailing = Uint8List(0);
    _evmsgAllTextStarts.clear();
    _evmsgAllTextEnds.clear();
    _evmsgAllStringIdx.clear();
    final data = File(ukDataPath).readAsBytesSync();
    _rawData = data;

    if (isEvMsg) {
      _loadEvMsg(data);
    } else if (isMessageV361) {
      _loadMessageV361(data);
    } else if (hasPair && offsetPath != null) {
      _loadPaired(data);
    } else if (inPlace) {
      _loadInPlace(data);
    } else {
      _loadSingle(data);
    }
  }

  // -----------------------------------------------------------------------
  // Formato EvMsg (binl com magic "EvMsgXX"):
  //   Bytes 0-4: "EvMsg" (magic fixo)
  //   Bytes 5-6: código de idioma ("UK", "SP", etc.)
  //   Byte 7:    versão
  //   Entradas de texto: 07 0C 00 [bytes de texto] 05 [separador]
  //     - O byte 05 termina o texto e inicia o separador (compartilhado)
  //     - Texto pode conter 0x00 e 0x02 como códigos de controle internos
  //     - breakOnEnd=false necessário para decodificar o range completo
  // -----------------------------------------------------------------------
  void _loadEvMsg(Uint8List data) {
    // Localiza todos os marcadores 07 0C 00 de uma vez
    final List<int> markers = [];
    for (int i = 0; i < data.length - 2; i++) {
      if (data[i] == 0x07 && data[i + 1] == 0x0C && data[i + 2] == 0x00) {
        markers.add(i);
      }
    }

    // Cada entrada: texto vai de (marker+3) até o próximo marker (ou fim do arquivo).
    // Funciona para ambos os subformatos:
    //   Tipo A (dc01): 07 0C 00 [texto] 05 [separador 8 bytes] 07 0C 00 ...
    //   Tipo B (di01): 07 0C 00 [texto 04] 07 0C 00 [texto 04] ...
    // O separador/terminador (05, 04, etc.) faz parte do bloco "texto" e sobrevive
    // ao round-trip encode/decode como [C:05], [C:04], [?:00], etc.
    for (int i = 0; i < markers.length; i++) {
      final textStart = markers[i] + 3;
      final textEnd   = (i + 1 < markers.length) ? markers[i + 1] : data.length;

      _evmsgAllTextStarts.add(textStart);
      _evmsgAllTextEnds.add(textEnd);

      // Decodifica com breakOnEnd=false (0x00/0x02/0x04/0x05 são códigos de controle)
      final decoded = KH1Encoding.decode(
        data.sublist(textStart, textEnd),
        breakOnEnd: false,
      );
      // Filtra: só inclui entradas com conteúdo alfabético real
      final alpha = decoded.replaceAll(RegExp(r'\[[^\]]+\]'), '').trim();
      if (alpha.length >= 2 && alpha.contains(RegExp(r'[a-zA-Z]'))) {
        _evmsgAllStringIdx.add(strings.length);
        _rawOffsets.add(textStart);
        strings.add(decoded);
      } else {
        _evmsgAllStringIdx.add(-1); // não é texto real, preservar verbatim
      }
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

  // -----------------------------------------------------------------------
  // Formato "Message v361" (sysmsg.binl): header + tabela de offsets LE16
  // Estrutura:
  //   0x00-0x0B  "Message v361"        (magic, 12 bytes)
  //   0x0C       count LE32            (número de strings, ex: 488 = 0x1E8)
  //   0x10       tbl_start LE32        (início da tabela = 0x0020)
  //   0x14       data_start LE32       (início dos dados = 0x03F2 para 488 strings)
  //   0x18       tbl_size LE32         (tamanho da tabela = (count+1)*2)
  //   0x1C       data_size LE32        (tamanho dos dados — varia por idioma)
  //   0x20       tabela: (count+1) x LE16, offsets relativos ao data_start
  //   0x03F2+    string data (null-terminated, 0x00 ou 0x02)
  // -----------------------------------------------------------------------
  void _loadMessageV361(Uint8List data) {
    final bd = data.buffer.asByteData();
    final count    = bd.getUint32(0x0C, Endian.little);
    final tblStart = bd.getUint32(0x10, Endian.little);
    final datStart = bd.getUint32(0x14, Endian.little);
    final datSize  = bd.getUint32(0x1C, Endian.little);

    // Sentinel value = last entry in table (total size of slot data, NOT counting trailing padding)
    int sentinelVal = 0;

    for (int i = 0; i < count; i++) {
      final offA = bd.getUint16(tblStart + i * 2,       Endian.little);
      final offB = bd.getUint16(tblStart + (i + 1) * 2, Endian.little);
      if (i == count - 1) sentinelVal = offB;
      final abs     = datStart + offA;
      final slotEnd = datStart + offB;
      // Encontra o primeiro terminador (0x00 ou 0x02) dentro do slot
      int textEnd = slotEnd;
      for (int j = abs; j < slotEnd; j++) {
        if (data[j] == 0x00 || data[j] == 0x02) { textEnd = j; break; }
      }
      _rawOffsets.add(abs);
      strings.add(KH1Encoding.decode(data.sublist(abs, textEnd)));
      // Sufixo: do primeiro terminador até o fim do slot (inclui terminador + bytes extras)
      _rawSuffixes.add(data.sublist(textEnd, slotEnd));
    }

    // Preserva bytes de padding após todos os slots (dat_size pode ser > sentinel)
    // esses bytes ficam DEPOIS do sentinel e são preservados separadamente
    final trailingStart = datStart + sentinelVal;
    final trailingEnd   = datStart + datSize;
    if (trailingEnd > trailingStart) {
      _rawMsgTrailing = data.sublist(trailingStart, trailingEnd);
    }
  }

  // Para arquivos binários mistos (.ev): só extrai strings com texto real
  void _loadInPlace(Uint8List data) {
    int pos = 0;
    while (pos < data.length) {
      int end = pos;
      while (end < data.length && data[end] != 0x00 && data[end] != 0x02) {
        end++;
      }
      if (end > pos) {
        final str = KH1Encoding.decode(data.sublist(pos, end));
        // Só inclui strings com conteúdo alfabético real (filtra lixo binário)
        final alpha = str.replaceAll(RegExp(r'\[[^\]]+\]'), '');
        if (alpha.trim().length >= 3 && alpha.contains(RegExp(r'[a-zA-Z]'))) {
          _rawOffsets.add(pos);
          strings.add(str);
        }
      }
      pos = end + 1;
      if (pos >= data.length) break;
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
      // Encontra fim de string.
      // nullOnly=true (arquivos Help): só divide em 0x00 — 0x02 é separador de linha interno.
      // nullOnly=false (padrão): divide em 0x00 ou 0x02 (formato exchange normal).
      int end = pos;
      if (nullOnly) {
        while (end < data.length && data[end] != 0x00) end++;
      } else {
        while (end < data.length && data[end] != 0x00 && data[end] != 0x02) end++;
      }

      // Rastreia TODAS as posições (incluindo vagas vazias) para preservar raw index
      _rawAllPositions.add(pos);

      if (end > pos) {
        // Segmento não-vazio
        _rawAllIsEmpty.add(false);
        _rawOffsets.add(pos);
        // nullOnly: decodifica sem parar em 0x02 (é separador interno, não terminador)
        strings.add(KH1Encoding.decode(data.sublist(pos, end), breakOnEnd: !nullOnly));
      } else {
        // Vaga vazia — preserva na estrutura para reconstrução correta
        _rawAllIsEmpty.add(true);
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

  // Retorna o espaço máximo disponível para a string i no arquivo original
  int maxStringLen(int index) {
    if (index < 0 || index >= _rawOffsets.length) return 0;
    return _rawStringLen(_rawOffsets[index]);
  }

  // Comprimento original da string no raw data
  int _rawStringLen(int offset) {
    int len = 0;
    while (offset + len < _rawData.length &&
           _rawData[offset + len] != 0x00 &&
           _rawData[offset + len] != 0x02) len++;
    return len;
  }

  // -----------------------------------------------------------------------
  // Serializa e salva byte a byte no caminho SP de destino
  // -----------------------------------------------------------------------
  void save(String outputBase) {
    final spFileName = _outputFilename(ukDataPath);
    final relPath = _relativePathFromExchange(ukDataPath);
    final outDir = Directory('$outputBase/$relPath');
    outDir.createSync(recursive: true);

    if (isEvMsg) {
      _saveEvMsg(outDir.path, spFileName);
    } else if (isMessageV361) {
      _saveMessageV361(outDir.path, spFileName);
    } else if (hasPair && offsetPath != null) {
      _savePaired(outDir.path, spFileName);
    } else if (inPlace) {
      _saveInPlace(outDir.path, spFileName);
    } else {
      _saveSingle(outDir.path, spFileName);
    }
  }

  // Reconstrói arquivo EvMsg substituindo apenas as regiões de texto traduzidas.
  // Toda a estrutura (cabeçalho, marcadores 07 0C 00, byte 05, separadores) é copiada
  // verbatim — só os bytes de texto entre 07 0C 00 e 05 são substituídos.
  // O arquivo pode crescer ou encolher livremente (não é patch in-place).
  void _saveEvMsg(String outDirPath, String spFileName) {
    final data = _rawData;
    final List<int> out = [];
    int pos = 0;

    for (int i = 0; i < _evmsgAllTextStarts.length; i++) {
      final tStart = _evmsgAllTextStarts[i];
      final tEnd   = _evmsgAllTextEnds[i];
      final si     = _evmsgAllStringIdx[i];

      // Copia tudo antes do início do texto (inclui 07 0C 00 e separadores anteriores)
      out.addAll(data.sublist(pos, tStart));

      if (si >= 0 && si < strings.length) {
        // Entrada com texto real: escreve tradução codificada
        out.addAll(KH1Encoding.encode(strings[si]));
      } else {
        // Entrada sem texto real (binário/controle): copia verbatim
        out.addAll(data.sublist(tStart, tEnd));
      }

      // Avança pos para o byte 05 (será copiado junto com o próximo bloco)
      pos = tEnd;
    }

    // Copia o resto do arquivo (byte 05 final, separadores, etc.)
    out.addAll(data.sublist(pos));

    File('$outDirPath/$spFileName').writeAsBytesSync(Uint8List.fromList(out));
  }

  void _saveMessageV361(String outDirPath, String spFileName) {
    // Reconstrói o arquivo preservando o header "Message v361" e a tabela de offsets.
    // Cada slot é: encode(translatedText) + sufixo original (terminador + bytes extras).
    // Strings podem crescer/encolher livremente — sem truncamento.
    final bd = _rawData.buffer.asByteData();

    // Constrói novo buffer de string data
    final List<int> strData = [];
    final List<int> newOffsets = []; // offsets relativos ao datStart

    for (int i = 0; i < strings.length; i++) {
      newOffsets.add(strData.length);
      strData.addAll(KH1Encoding.encode(strings[i]));
      // Adiciona sufixo original (inclui terminador 0x00/0x02 + bytes extras do slot)
      if (i < _rawSuffixes.length && _rawSuffixes[i].isNotEmpty) {
        strData.addAll(_rawSuffixes[i]);
      } else {
        strData.add(0x00); // fallback: terminador nulo
      }
    }
    // Sentinel: aponta para o fim de todos os slots (ANTES do trailing padding)
    newOffsets.add(strData.length);
    // Adiciona trailing padding após o sentinel (bytes extra que o arquivo original tem)
    strData.addAll(_rawMsgTrailing);

    // Reconstrói o arquivo completo
    final out = <int>[];
    // Header original bytes 0x00-0x1B (magic + count + tblStart + datStart + tblSize)
    out.addAll(_rawData.sublist(0, 0x1C));
    // data_size (0x1C-0x1F): novo tamanho total dos dados
    final newDataSize = strData.length;
    out.add(newDataSize & 0xFF);
    out.add((newDataSize >> 8) & 0xFF);
    out.add((newDataSize >> 16) & 0xFF);
    out.add((newDataSize >> 24) & 0xFF);
    // Tabela de offsets: (count+1) entradas LE16
    for (final o in newOffsets) {
      out.add(o & 0xFF);
      out.add((o >> 8) & 0xFF);
    }
    // String data
    out.addAll(strData);

    File('$outDirPath/$spFileName').writeAsBytesSync(Uint8List.fromList(out));
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
    final spOffsetName = _outputFilename(offsetPath!);
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

  // Patch in-place: substitui strings no binário original sem alterar estrutura
  void _saveInPlace(String outDirPath, String spFileName) {
    final bytes = Uint8List.fromList(_rawData);
    for (int i = 0; i < strings.length && i < _rawOffsets.length; i++) {
      final off = _rawOffsets[i];
      final encoded = KH1Encoding.encode(strings[i]);
      // Calcula tamanho original da string no arquivo
      int origLen = 0;
      while (off + origLen < bytes.length &&
             bytes[off + origLen] != 0x00 &&
             bytes[off + origLen] != 0x02) {
        origLen++;
      }
      // Escreve bytes novos (limitado ao tamanho original)
      for (int j = 0; j < origLen && j < encoded.length; j++) {
        bytes[off + j] = encoded[j];
      }
      // Preenche resto com 0x00 se string nova é menor
      for (int j = encoded.length; j < origLen; j++) {
        bytes[off + j] = 0x00;
      }
    }
    File('$outDirPath/$spFileName').writeAsBytesSync(bytes);
  }

  void _saveSingle(String outDirPath, String spFileName) {
    // Reconstrói preservando vagas vazias (empty slots) do arquivo original.
    // CRÍTICO: o game busca strings por índice sequencial (raw index contando \0s),
    // não por byte offset. Perder as vagas vazias desloca todos os índices e faz o
    // game carregar strings erradas. Strings podem crescer/diminuir livremente.
    final List<int> newData = [];

    // Preserva header de contagem se existia (primeiros 4 bytes)
    if (_rawData.length > 4) {
      final count = _rawData.buffer.asByteData().getUint32(0, Endian.little);
      if (count < 300 && count > 0) {
        newData.addAll(_rawData.sublist(0, 4));
      }
    }

    // Detecta terminador original (0x00 ou 0x02) para preservar formato
    int terminator = 0x00;
    if (_rawOffsets.isNotEmpty) {
      int pos = _rawOffsets[0];
      while (pos < _rawData.length &&
             _rawData[pos] != 0x00 &&
             _rawData[pos] != 0x02) pos++;
      if (pos < _rawData.length) terminator = _rawData[pos];
    }

    // Escreve todas as posições: vagas vazias (só terminador) e strings traduzidas
    int stringIdx = 0;
    for (int i = 0; i < _rawAllPositions.length; i++) {
      if (_rawAllIsEmpty[i]) {
        // Vaga vazia: preserva como terminador único (raw index mantido)
        newData.add(terminator);
      } else {
        // String real: escreve tradução + terminador (pode ser maior ou menor)
        final encoded = KH1Encoding.encode(strings[stringIdx]);
        newData.addAll(encoded);
        newData.add(terminator);
        stringIdx++;
      }
    }

    File('$outDirPath/$spFileName').writeAsBytesSync(Uint8List.fromList(newData));
  }

  // Helpers
  static String _outputFilename(String ukPath) {
    return ukPath.split('/').last;
  }

  static String _relativePathFromExchange(String fullPath) {
    // Retorna "kh1_first/original/exchange" (SEM .hed_out no nome da pasta)
    final parts = fullPath.split('/');
    final hedIdx = parts.indexWhere((p) => p.endsWith('.hed_out'));
    if (hedIdx == -1) return 'exchange';
    // Remove o sufixo .hed_out do nome da pasta
    final hedDirName = parts[hedIdx].replaceAll('.hed_out', '');
    final subParts = [hedDirName, ...parts.sublist(hedIdx + 1, parts.length - 1)];
    return subParts.join('/');
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
  Function(String error)? onError;
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
  // Verifica se um arquivo é texto KH1 válido (exclui TTUI, EVM, kanji, etc.)
  // -----------------------------------------------------------------------
  static bool _isTextFile(Uint8List data, String filename) {
    if (data.length < 4) return false;

    // TTUI = UI layout (coordenadas, definições de elementos, NÃO texto)
    if (data[0] == 0x54 && data[1] == 0x54 && data[2] == 0x55 && data[3] == 0x49) return false;

    // EVM = cutscene/evento (sem texto KH1 acessível)
    if (data[0] == 0x45 && data[1] == 0x56 && data[2] == 0x4D && data[3] == 0x00) return false;

    // REDL = dados de eventos internos
    if (data.length >= 4 && String.fromCharCodes(data.take(4)) == 'REDL') return false;

    // Kanji table - arquivo muito grande de zeros/binário puro
    if (filename.endsWith('.knj')) return false;

    // Arquivos .nam = formato binário "Message v360" embutido (allarea.nam, wname.nam, etc.)
    // NÃO são exchange text puro — contêm header binário + multiple Message v360 sections
    if (filename.endsWith('.nam')) return false;

    // Offset-only files (_offset.bin, _ofs.bin) - só ponteiros, sem texto real
    if (filename.contains('_offset.bin') || filename.contains('_ofs.bin')) return false;

    // Font tables
    if (filename.contains('font') || filename.endsWith('sysfont.bin')) return false;

    return true;
  }

  // -----------------------------------------------------------------------
  // Escaneia todos os arquivos de texto (exchange + remastered)
  // -----------------------------------------------------------------------
  List<ExchangeFile> scanFiles() {
    final result = <ExchangeFile>[];
    result.addAll(_scanExchange());
    result.addAll(_scanRemasteredBtltbl());
    result.addAll(_scanRemasteredEv());
    result.addAll(_scanRemasteredMenu());
    return result;
  }

  // -----------------------------------------------------------------------
  // Escaneia remastered/btltbl.bin/ (habilidades, itens)
  // -----------------------------------------------------------------------
  List<ExchangeFile> _scanRemasteredBtltbl() {
    final btltblDir = Directory('$hedOutPath/remastered/btltbl.bin');
    if (!btltblDir.existsSync()) return [];
    final result = <ExchangeFile>[];
    for (final f in btltblDir.listSync().whereType<File>()) {
      final name = f.path.split('/').last;
      if (!name.startsWith('UK_') || !name.endsWith('.bin')) continue;
      final rawBytes = f.readAsBytesSync();
      if (!_isTextFile(rawBytes, name)) continue;
      // inPlace: false → _saveSingle() com preservação de vagas vazias (empty slots)
      // O game busca strings por índice sequencial (raw index), não byte offset.
      // Comprovado: UK/SP/FR/IT/GR todas têm "Kingdom Key" em raw[110] mas com
      // byte offsets diferentes. Empty slots devem ser preservados no rebuild.
      // Arquivos Help (AbilityHelp, ItemHelp) usam 0x02 como separador de linha INTERNO
      // dentro de strings null-terminated. nullOnly=true evita divisão incorreta em 0x02.
      final isHelpFile = name.contains('Help');
      result.add(ExchangeFile(
        ukDataPath: f.path,
        spDataPath: f.path.replaceFirst('/UK_', '/SP_'),
        hasPair: false,
        nullOnly: isHelpFile,
      ));
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // Escaneia remastered/*.ard/UK_*.ev (legendas de cutscene)
  // Arquivos EvMsg (magic "EvMsg"): isEvMsg=true, inPlace=false (rebuild livre)
  // Outros .ev/.evdl/.binl: inPlace=true (patch no lugar)
  // -----------------------------------------------------------------------
  List<ExchangeFile> _scanRemasteredEv() {
    final remasteredDir = Directory('$hedOutPath/remastered');
    if (!remasteredDir.existsSync()) return [];
    final result = <ExchangeFile>[];
    for (final entry in remasteredDir.listSync().whereType<Directory>()) {
      if (!entry.path.split('/').last.endsWith('.ard')) continue;
      for (final f in entry.listSync().whereType<File>()) {
        final name = f.path.split('/').last;
        if (!name.startsWith('UK_')) continue;
        if (!name.endsWith('.ev') && !name.endsWith('.evdl') && !name.endsWith('.binl')) continue;
        final raw = f.readAsBytesSync();
        final evMsg = _isEvMsg(raw);
        result.add(ExchangeFile(
          ukDataPath: f.path,
          spDataPath: f.path.replaceFirst('/UK_', '/SP_'),
          hasPair: false,
          inPlace: !evMsg,  // EvMsg é reconstruído, outros são patchados no lugar
          isEvMsg: evMsg,
        ));
      }
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // Escaneia remastered/menu/uk/**/ (Load Menu, System Messages HD)
  // -----------------------------------------------------------------------
  List<ExchangeFile> _scanRemasteredMenu() {
    final result = <ExchangeFile>[];
    // remastered/menu/uk/ contém subpastas (ex: sysmsg.bin/) com UK_*.binl
    final menuUkDir = Directory('$hedOutPath/remastered/menu/uk');
    if (!menuUkDir.existsSync()) return result;
    _scanDirRecursive(menuUkDir, result);
    return result;
  }

  // Detecta se um arquivo é formato EvMsg (magic "EvMsg" nos primeiros 5 bytes)
  static bool _isEvMsg(Uint8List data) {
    if (data.length < 8) return false;
    return data[0] == 0x45 && data[1] == 0x76 && data[2] == 0x4D &&
           data[3] == 0x73 && data[4] == 0x67; // "EvMsg"
  }

  // Detecta se um arquivo é formato "Message v361"
  static bool _isMessageV361(Uint8List data) {
    if (data.length < 16) return false;
    const magic = [0x4D,0x65,0x73,0x73,0x61,0x67,0x65,0x20,0x76,0x33,0x36,0x31]; // "Message v361"
    for (int i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return false;
    }
    return true;
  }

  // Auxiliar: escaneia recursivamente diretório por UK_*.{binl,bin,ev,evdl}
  void _scanDirRecursive(Directory dir, List<ExchangeFile> result) {
    for (final entry in dir.listSync()) {
      if (entry is File) {
        final name = entry.path.split('/').last;
        if (!name.startsWith('UK_')) continue;
        final lower = name.toLowerCase();
        if (!lower.endsWith('.binl') && !lower.endsWith('.bin') &&
            !lower.endsWith('.ev') && !lower.endsWith('.evdl')) continue;

        // Detecta formato "Message v361" para salvar corretamente sem truncar
        final raw = entry.readAsBytesSync();
        final isMsg = _isMessageV361(raw);

        result.add(ExchangeFile(
          ukDataPath: entry.path,
          spDataPath: entry.path.replaceFirst('/UK_', '/SP_'),
          hasPair: false,
          inPlace: !isMsg,         // inPlace só para ev/evdl normais
          isMessageV361: isMsg,    // sysmsg.binl → rebuild com tabela
        ));
      } else if (entry is Directory) {
        _scanDirRecursive(entry, result);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Escaneia original/exchange/ (textos de menu/UI)
  // -----------------------------------------------------------------------
  List<ExchangeFile> _scanExchange() {
    final exchangeDir = Directory('$hedOutPath/original/exchange');
    if (!exchangeDir.existsSync()) return [];

    final files = exchangeDir.listSync().whereType<File>().toList();
    final List<ExchangeFile> result = [];
    final Set<String> handled = {};

    for (final f in files) {
      final name = f.path.split('/').last;
      if (!name.startsWith('UK_')) continue;
      if (handled.contains(name)) continue;

      // Valida se é arquivo de texto antes de incluir
      final rawBytes = f.readAsBytesSync();
      if (!_isTextFile(rawBytes, name)) continue;

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
  // Traduz todos os arquivos — N arquivos concorrentes, strings sequenciais
  // por arquivo (mais simples e sem race conditions no save)
  // -----------------------------------------------------------------------
  Future<void> translateAll(List<ExchangeFile> files) async {
    int totalStrings = 0;
    int doneStrings = 0;
    int translated = 0;
    int skipped = 0;
    int errors = 0;
    int consecutiveErrors = 0;
    const int maxConsecutiveErrors = 8;

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

    // Processa um arquivo completo (strings em sequência), depois salva
    Future<void> translateFile(ExchangeFile ef) async {
      if (cancelled) return;
      final fileName = ef.ukDataPath.split('/').last;

      for (int si = 0; si < ef.strings.length; si++) {
        if (cancelled) return;

        final original = ef.strings[si];
        final clean = original
            .replaceAll(RegExp(r'\[(?:C|BTN|\?):[\dA-Fa-f]{2}\]'), '')
            .trim();

        if (clean.length < 2 || clean.length > 3000) {
          if (clean.length > 3000) {
            print('[SKIP] $fileName [str $si]: string muito longa (${clean.length} chars)');
          }
          skipped++;
        } else {
          try {
            final Map<String, String> prot = {};
            final toTranslate = KH1Encoding.protectTerms(original, prot);

            // Tenta até 2 vezes (retry em timeout/erro transitório)
            Translation? translation;
            for (int attempt = 0; attempt < 2; attempt++) {
              try {
                translation = await _translator.translate(
                  toTranslate,
                  from: 'en',
                  to: 'pt',
                ).timeout(const Duration(seconds: 15));
                break;
              } catch (_) {
                if (attempt == 0) {
                  await Future.delayed(const Duration(seconds: 3));
                } else {
                  rethrow;
                }
              }
            }

            String translatedText = translation!.text;
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
              // Remover \n do texto traduzido — o game trata 0x0A como fim de string
              translatedText = translatedText.replaceAll('\n', ' ').trim();
              ef.editString(si, translatedText);
              translated++;
            }
            consecutiveErrors = 0;
          } catch (e) {
            errors++;
            consecutiveErrors++;
            print('[ERRO] $fileName [str $si]: ${e.runtimeType}: $e');
            await Future.delayed(const Duration(seconds: 2));
            if (consecutiveErrors >= maxConsecutiveErrors) {
              cancelled = true;
              onError?.call(
                'API indisponível após $consecutiveErrors erros consecutivos. '
                'Traduzidas: $translated | Puladas: $skipped | Erros: $errors',
              );
            }
          }
        }

        doneStrings++;
        onProgress?.call(doneStrings, totalStrings,
            '$fileName [$si/${ef.strings.length}]');
      }

      // Salva após TODAS as strings do arquivo estarem prontas
      if (!cancelled) {
        try {
          ef.save(outputBase);
        } catch (e) {
          print('[ERRO] Save $fileName: $e');
          errors++;
        }
      }
    }

    // N arquivos concorrentes (cada um processa suas strings em sequência)
    const int maxConcurrentFiles = 8;
    for (int fi = 0; fi < files.length; fi += maxConcurrentFiles) {
      if (cancelled) break;
      final end = (fi + maxConcurrentFiles).clamp(0, files.length);
      await Future.wait(
        List.generate(end - fi, (k) => translateFile(files[fi + k])),
      );
    }

    onDone?.call('Traduzidas: $translated | Puladas: $skipped | Erros: $errors');
  }
}
