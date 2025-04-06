import 'package:translator_plus/translator_plus.dart';

//Programado por HeroRickyGAMES com a ajuda de Deus!

String traduzido = '';
final translator = GoogleTranslator();

Future<String> TradutorClass(String Texto) async {
  final extract = translator.translate(Texto, from: 'en', to: 'pt').then((s) {
    return "$s";
  });

  return extract;
}