import 'package:timeago/timeago.dart';

class ClashCustomMessages implements LookupMessages {
  @override
  String prefixAgo() => '';

  @override
  String prefixFromNow() => '';

  @override
  String suffixAgo() => '前';

  @override
  String suffixFromNow() => '后';

  @override
  String lessThanOneMinute(int seconds) => '几秒';

  @override
  String aboutAMinute(int minutes) => '约一分钟';

  @override
  String minutes(int minutes) => '$minutes 分钟';

  @override
  String aboutAnHour(int minutes) => '约一小时';

  @override
  String hours(int hours) => '$hours 小时';

  @override
  String aDay(int hours) => '约一天';

  @override
  String days(int days) => '$days 天';

  @override
  String aboutAMonth(int days) => '约一月';

  @override
  String months(int months) => '$months 月';

  @override
  String aboutAYear(int year) => '约一年';

  @override
  String years(int years) => '$years 年';

  @override
  String wordSeparator() => '';
}
