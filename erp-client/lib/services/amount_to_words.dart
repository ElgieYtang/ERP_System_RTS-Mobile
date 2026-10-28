/// Mirrors `frontend/src/lib/numberToWords.js`.
String amountToPesoWords(num amount) {
  final value = amount.toDouble();
  if (value.isNaN) return '';

  final whole = value.floor();
  final cents = ((value - whole) * 100).round();

  if (cents > 0) {
    return '${_integerToWords(whole)} PESOS AND ${_integerToWords(cents)} CENTAVOS ONLY';
  }
  return '${_integerToWords(whole)} PESOS ONLY';
}

const _ones = [
  '',
  'ONE',
  'TWO',
  'THREE',
  'FOUR',
  'FIVE',
  'SIX',
  'SEVEN',
  'EIGHT',
  'NINE',
  'TEN',
  'ELEVEN',
  'TWELVE',
  'THIRTEEN',
  'FOURTEEN',
  'FIFTEEN',
  'SIXTEEN',
  'SEVENTEEN',
  'EIGHTEEN',
  'NINETEEN',
];

const _tens = ['', '', 'TWENTY', 'THIRTY', 'FORTY', 'FIFTY', 'SIXTY', 'SEVENTY', 'EIGHTY', 'NINETY'];

String _integerToWords(int value) {
  if (value == 0) return 'ZERO';

  final millions = value ~/ 1000000;
  final thousands = (value % 1000000) ~/ 1000;
  final remainder = value % 1000;
  final leading = <String>[];

  if (millions > 0) leading.add('${_chunkToWords(millions)} MILLION');
  if (thousands > 0) leading.add('${_chunkToWords(thousands)} THOUSAND');

  if (leading.isNotEmpty && remainder > 0) {
    return '${leading.join(' ')} AND ${_chunkToWords(remainder)}';
  }
  if (leading.isNotEmpty) return leading.join(' ');
  return _chunkToWords(remainder);
}

String _chunkToWords(int value) {
  if (value == 0) return '';

  final hundred = value ~/ 100;
  final rest = value % 100;
  final parts = <String>[];

  if (hundred > 0) parts.add('${_ones[hundred]} HUNDRED');
  if (rest > 0) {
    if (rest < 20) {
      parts.add(_ones[rest]);
    } else {
      final ten = rest ~/ 10;
      final one = rest % 10;
      parts.add(one > 0 ? '${_tens[ten]} ${_ones[one]}' : _tens[ten]);
    }
  }
  return parts.join(' ');
}
