import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../backend/backend_models.dart';

class ReceiptScanner {
  const ReceiptScanner();

  Future<ReceiptExtraction> scan(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final chineseRecognizer = TextRecognizer(
      script: TextRecognitionScript.chinese,
    );
    try {
      final results = await Future.wait([
        latinRecognizer.processImage(image),
        chineseRecognizer.processImage(image),
      ]);
      final latin = results[0].text.trim();
      final chinese = results[1].text.trim();
      final useChinese = chinese.length > latin.length * 1.15;
      final selected = useChinese ? chinese : latin;
      return ReceiptParser.parse(
        selected,
        script: useChinese ? 'chinese' : 'latin',
      );
    } finally {
      await latinRecognizer.close();
      await chineseRecognizer.close();
    }
  }
}

class ReceiptParser {
  static final RegExp _moneyAtEnd = RegExp(
    r'(?:RM|MYR|\$)?\s*(-?\d{1,6}(?:[.,]\d{2}))\s*$',
    caseSensitive: false,
  );
  static final RegExp _date = RegExp(
    r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b|'
    r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2}|\d{2})\b',
  );
  static final RegExp _merchantNoise = RegExp(
    r'(receipt|invoice|tax|tel|phone|address|cashier|welcome|thank)',
    caseSensitive: false,
  );
  static final RegExp _totalLabel = RegExp(
    r'\b(grand\s*total|total\s*(amount|due)?|amount\s*due|net\s*total)\b',
    caseSensitive: false,
  );
  static final RegExp _excludedTotal = RegExp(
    r'\b(sub\s*total|subtotal|change|cash|rounding|tax|service)\b',
    caseSensitive: false,
  );

  static ReceiptExtraction parse(String rawText, {String script = 'latin'}) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return ReceiptExtraction(
      rawText: rawText.trim(),
      merchant: _merchant(lines),
      total: _total(lines),
      date: _receiptDate(lines),
      items: _items(lines),
      script: script,
    );
  }

  static String _merchant(List<String> lines) {
    for (final line in lines.take(6)) {
      final letterCount = RegExp(
        r'[A-Za-z\u3400-\u9FFF]',
      ).allMatches(line).length;
      if (letterCount >= 3 &&
          line.length <= 80 &&
          !_merchantNoise.hasMatch(line) &&
          !_moneyAtEnd.hasMatch(line)) {
        return line;
      }
    }
    return '';
  }

  static double? _total(List<String> lines) {
    final labelled = <double>[];
    final fallback = <double>[];
    for (final line in lines) {
      final match = _moneyAtEnd.firstMatch(line);
      if (match == null) continue;
      final value = _parseMoney(match.group(1));
      if (value == null || value <= 0) continue;
      if (_totalLabel.hasMatch(line) && !_excludedTotal.hasMatch(line)) {
        labelled.add(value);
      } else if (!_excludedTotal.hasMatch(line)) {
        fallback.add(value);
      }
    }
    if (labelled.isNotEmpty) return labelled.last;
    if (fallback.isEmpty) return null;
    return fallback.reduce((left, right) => left > right ? left : right);
  }

  static DateTime? _receiptDate(List<String> lines) {
    for (final line in lines) {
      final match = _date.firstMatch(line);
      if (match == null) continue;
      int year;
      int month;
      int day;
      if (match.group(1) != null) {
        year = int.parse(match.group(1)!);
        month = int.parse(match.group(2)!);
        day = int.parse(match.group(3)!);
      } else {
        day = int.parse(match.group(4)!);
        month = int.parse(match.group(5)!);
        year = int.parse(match.group(6)!);
        if (year < 100) year += 2000;
      }
      final parsed = DateTime.tryParse(
        '$year-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}',
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  static List<ReceiptItem> _items(List<String> lines) {
    final items = <ReceiptItem>[];
    for (final line in lines) {
      if (_totalLabel.hasMatch(line) || _excludedTotal.hasMatch(line)) continue;
      final match = _moneyAtEnd.firstMatch(line);
      if (match == null || match.start < 2) continue;
      final description = line.substring(0, match.start).trim();
      final amount = _parseMoney(match.group(1));
      if (description.length < 2 || amount == null || amount <= 0) continue;
      items.add(ReceiptItem(description: description, amount: amount));
      if (items.length == 50) break;
    }
    return items;
  }

  static double? _parseMoney(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }
}
