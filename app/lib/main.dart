import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  // Если локальная зона не определится — fallback к Europe/Moscow
  try {
    // На CI это безопасно: просто используем локальную по умолчанию
    tz.setLocalLocation(tz.local);
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
  }
  await _Notif.init();
  runApp(const BPApp());
}

class BPApp extends StatelessWidget {
  const BPApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мониторинг давления',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6A5ACD),
        fontFamily: 'Roboto',
      ),
      home: const Home(),
    );
  }
}

class BPRecord {
  final DateTime ts;
  final int sys;
  final int dia;
  final int? pulse;
  final String? note;

  BPRecord({required this.ts, required this.sys, required this.dia, this.pulse, this.note});

  Map<String, dynamic> toMap() => {
        'ts': ts.toIso8601String(),
        'sys': sys,
        'dia': dia,
        'pulse': pulse,
        'note': note,
      };

  factory BPRecord.fromMap(Map<String, dynamic> m) => BPRecord(
        ts: DateTime.parse(m['ts'] as String),
        sys: (m['sys'] as num).toInt(),
        dia: (m['dia'] as num).toInt(),
        pulse: (m['pulse'] as num?)?.toInt(),
        note: m['note'] as String?,
      );

  static String csvHeader() => 'timestamp;date;time;sys;dia;pulse;note';
  String toCsv() {
    final d = DateFormat('yyyy-MM-dd').format(ts);
    final t = DateFormat('HH:mm').format(ts);
    return '${ts.toIso8601String()};$d;$t;$sys;$dia;${pulse ?? ''};"${(note ?? '').replaceAll('"', '""')}"';
  }
}

class Repo {
  static const _key = 'bp_records_v2';
  static Future<List<BPRecord>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(BPRecord.fromMap).toList()..sort((a, b) => b.ts.compareTo(a.ts));
  }

  static Future<void> save(List<BPRecord> items) async {
    items.sort((a, b) => b.ts.compareTo(a.ts));
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((e) => e.toMap()).toList());
    await sp.setString(_key, raw);
  }
}

/// Уведомления
class _Notif {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'reminders_channel';

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    final impl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      'Напоминания',
      description: 'Напоминания о замерах давления',
      importance: Importance.high,
    ));
  }

  static Future<int> scheduleOnce(DateTime when, String body) async {
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    await _plugin.zonedSchedule(
      id,
      'Пора измерить давление',
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'Напоминания',
            channelDescription: 'Напоминания о замерах давления',
            priority: Priority.high,
            importance: Importance.high),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
    return id;
  }

  static Future<int> scheduleDaily(TimeOfDay tod, String body) async {
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    if (first.isBefore(now)) first = first.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id,
      'Ежедневное напоминание',
      body,
      tz.TZDateTime.from(first, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'Ежедневные',
            channelDescription: 'Ежедневные напоминания',
            priority: Priority.high,
            importance: Importance.high),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return id;
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);
}

/// Храним ID напоминаний
class RemindRepo {
  static const _key = 'bp_reminders_v1';
  static Future<List<Map<String, dynamic>>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> save(List<Map<String, dynamic>> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(items));
  }
}

enum Period { d24, d7, d30, custom }

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  final _note = TextEditingController();
  DateTime _pick = DateTime.now();

  List<BPRecord> _all = [];
  Period _period = Period.d7;
  DateTime? _from;
  DateTime? _to;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _all = await Repo.load();
    setState(() {});
  }

  List<BPRecord> get _filtered {
    DateTime from, to;
    final now = DateTime.now();
    switch (_period) {
      case Period.d24:
        from = now.subtract(const Duration(hours: 24));
        to = now;
        break;
      case Period.d7:
        from = now.subtract(const Duration(days: 7));
        to = now;
        break;
      case Period.d30:
        from = now.subtract(const Duration(days: 30));
        to = now;
        break;
      case Period.custom:
        from = _from ?? now.subtract(const Duration(days: 7));
        to = _to ?? now;
        break;
    }
    return _all.where((r) => r.ts.isAfter(from) && r.ts.isBefore(to.add(const Duration(seconds: 1)))).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
  }

  (double?, double?, double?) get _avg {
    final list = _filtered;
    if (list.isEmpty) return (null, null, null);
    final s = list.fold<int>(0, (a, b) => a + b.sys) / list.length;
    final d = list.fold<int>(0, (a, b) => a + b.dia) / list.length;
    final pList = list.where((e) => e.pulse != null).toList();
    final p = pList.isEmpty ? null : pList.fold<int>(0, (a, b) => a + b.pulse!) / pList.length;
    return (s, d, p);
  }

  Future<void> _save() async {
    final sys = int.tryParse(_sys.text.trim());
    final dia = int.tryParse(_dia.text.trim());
    if (sys == null || dia == null) {
      _snack('Нужно ввести SYS и DIA');
      return;
    }
    final pulse = _pulse.text.trim().isEmpty ? null : int.tryParse(_pulse.text.trim());
    final rec = BPRecord(ts: _pick, sys: sys, dia: dia, pulse: pulse, note: _note.text.trim().isEmpty ? null : _note.text.trim());
    _all.insert(0, rec);
    await Repo.save(_all);
    setState(() {
      _sys.clear();
      _dia.clear();
      _pulse.clear();
      _note.clear();
      _pick = DateTime.now();
    });
    _snack('Сохранено');
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _exportAndShare() async {
    final list = _filtered..sort((a, b) => a.ts.compareTo(b.ts)); // для CSV по возрастанию
    if (list.isEmpty) {
      _snack('Нет записей для экспорта');
      return;
    }
    final rows = [BPRecord.csvHeader(), ...list.map((e) => e.toCsv())].join('\n');
    final dir = Platform.isAndroid ? (await getExternalStorageDirectory())! : await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/bp_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv');
    await file.writeAsString(rows, encoding: const Utf8Codec());
    await Share.shareXFiles([XFile(file.path)], text: 'Экспорт давления (выбранный период)');
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2015), lastDate: DateTime(2100), initialDate: _pick);
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _pick.hour, minute: _pick.minute));
    final tt = t ?? TimeOfDay.now();
    setState(() => _pick = DateTime(d.year, d.month, d.day, tt.hour, tt.minute));
  }

  Future<void> _setPeriod(Period p) async {
    if (p == Period.custom) {
      final now = DateTime.now();
      final df = await showDatePicker(context: context, initialDate: now.subtract(const Duration(days: 7)), firstDate: DateTime(2015), lastDate: now);
      if (df == null) return;
      final dt = await showDatePicker(context: context, initialDate: now, firstDate: df, lastDate: DateTime(2100));
      if (dt == null) return;
      setState(() {
        _period = p;
        _from = df;
        _to = dt.add(const Duration(hours: 23, minutes: 59));
      });
    } else {
      setState(() => _period = p);
    }
  }

  Future<void> _addReminderOnce() async {
    final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: DateTime.now());
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    final when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    final id = await _Notif.scheduleOnce(when, DateFormat('dd.MM HH:mm').format(when));
    final list = await RemindRepo.load();
    list.add({'id': id, 'type': 'once', 'time': when.toIso8601String()});
    await RemindRepo.save(list);
    _snack('Напоминание добавлено');
    setState(() {});
  }

  Future<void> _addReminderDaily() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    final id = await _Notif.scheduleDaily(t, 'Ежедневно в ${t.format(context)}');
    final list = await RemindRepo.load();
    list.add({'id': id, 'type': 'daily', 'time': t.format(context)});
    await RemindRepo.save(list);
    _snack('Ежедневное напоминание добавлено');
    setState(() {});
  }

  Future<void> _delReminder(int id) async {
    await _Notif.cancel(id);
    final list = await RemindRepo.load();
    list.removeWhere((e) => e['id'] == id);
    await RemindRepo.save(list);
    _snack('Напоминание удалено');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ['Список', 'Графики', 'Напоминания'];
    final (avgSys, avgDia, avgPulse) = _avg;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Logger+'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt),
            onSelected: (v) {
              switch (v) {
                case '24ч':
                  _setPeriod(Period.d24);
                  break;
                case '7д':
                  _setPeriod(Period.d7);
                  break;
                case '30д':
                  _setPeriod(Period.d30);
                  break;
                case 'Период…':
                  _setPeriod(Period.custom);
                  break;
              }
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: '24ч', child: Text('Последние 24 часа')),
              PopupMenuItem(value: '7д', child: Text('Последние 7 дней')),
              PopupMenuItem(value: '30д', child: Text('Последние 30 дней')),
              PopupMenuItem(value: 'Период…', child: Text('Выбрать период…')),
            ],
          ),
          IconButton(icon: const Icon(Icons.ios_share), onPressed: _exportAndShare),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final sel = _tab == i;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                        child: Text(
                      tabs[i],
                      style: TextStyle(
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? Theme.of(context).colorScheme.primary : null),
                    )),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: switch (_tab) {
          0 => _buildList(avgSys, avgDia, avgPulse),
          1 => _buildCharts(),
          2 => _buildReminders(),
          _ => const SizedBox.shrink(),
        },
      ),
      bottomNavigationBar: _tab == 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Сохранить'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ),
    );
  }

  Widget _buildList(double? avgSys, double? avgDia, double? avgPulse) {
    final list = _filtered;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _inputs(),
        const SizedBox(height: 12),
        if (avgSys != null && avgDia != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Средние за период: ${avgSys.toStringAsFixed(0)}/${avgDia.toStringAsFixed(0)}'
              '${avgPulse != null ? ' • ${avgPulse.toStringAsFixed(0)} bpm' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ...list.map((e) => Card(
              child: ListTile(
                title: Text('${e.sys}/${e.dia}${e.pulse != null ? '   •   ${e.pulse} bpm' : ''}'),
                subtitle:
                    Text('${DateFormat('yyyy-MM-dd HH:mm').format(e.ts)}${e.note != null ? '\n${e.note}' : ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    _all.remove(e);
                    await Repo.save(_all);
                    setState(() {});
                  },
                ),
              ),
            )),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _inputs() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _outlined(_sys, 'SYS', keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: _outlined(_dia, 'DIA', keyboard: TextInputType.number)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _outlined(_note, 'Примечание (необязательно)')),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Дата/время',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 20),
                      const SizedBox(width: 8),
                      Text(DateFormat('yyyy-MM-dd HH:mm').format(_pick)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _outlined(_pulse, 'Пульс (необязательно)', keyboard: TextInputType.number)),
          ],
        ),
      ],
    );
  }

  Widget _outlined(TextEditingController c, String label, {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildCharts() {
    final list = _filtered..sort((a, b) => a.ts.compareTo(b.ts));
    final sys = <FlSpot>[];
    final dia = <FlSpot>[];
    for (var i = 0; i < list.length; i++) {
      sys.add(FlSpot(i.toDouble(), list[i].sys.toDouble()));
      dia.add(FlSpot(i.toDouble(), list[i].dia.toDouble()));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _lineCard('Систолическое (SYS)', sys),
        const SizedBox(height: 12),
        _lineCard('Диастолическое (DIA)', dia),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _lineCard(String title, List<FlSpot> spots) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: LineChart(LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: const FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    spots: spots,
                  ),
                ],
              )),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildReminders() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: RemindRepo.load(),
      builder: (c, s) {
        final list = s.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                    child: FilledButton.icon(
                  onPressed: _addReminderOnce,
                  icon: const Icon(Icons.alarm_add),
                  label: const Text('Одноразовое'),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: OutlinedButton.icon(
                  onPressed: _addReminderDaily,
                  icon: const Icon(Icons.repeat),
                  label: const Text('Ежедневное'),
                )),
              ],
            ),
            const SizedBox(height: 12),
            ...list.map((m) => Card(
                  child: ListTile(
                    title: Text(m['type'] == 'daily'
                        ? 'Ежедневно: ${m['time']}'
                        : 'Один раз: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(m['time']))}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delReminder(m['id'] as int),
                    ),
                  ),
                )),
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }
}
