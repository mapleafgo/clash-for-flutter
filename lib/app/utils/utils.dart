import 'package:clash_for_flutter/app/enum/type_enum.dart';

String dataformat(int value) {
  double num = value.toDouble();
  var level = 0;
  for (; num.compareTo(1024) > 0; level++) {
    num /= 1024;
  }
  return "${num.toStringAsFixed(1)} ${DataUnit.values[level].value}";
}
