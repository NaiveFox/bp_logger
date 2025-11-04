import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _Notifications.ensureInit();
  runApp(const BPApp());
}

class BPApp extends StatelessWidget {
  const BPApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мониторинг Давления',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C47A3)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// ====== Модель ======
class BPRecord {
  final DateTime ts;
  final int sys;
  final int dia;
  final int? pulse;
  final String? note;

  BPRecord({
    required this.ts,
    required this.sys,
    required this.dia,
    this.pulse,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'ts': ts.toIso8601String(),
        'sys': sys,
        'dia': dia,
        'pulse': pulse,
        'note': note,
      };

  factory BPRecord.fromMap(Map<String, dynamic> m) => BPRecord(
        ts: DateTime.parse(m['ts'] as String),
        sys: m['sys'] as int,
        dia: m['dia'] as int,
        pulse: (m['pulse'] as num?)?.toInt(),
        note: m['note'] as String?,
      );
}

/// ====== Хранилище ======
class BPStore {
  static const _key = 'bp_records_v2';
  static Future<List<BPRecord>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final out = list.map(BPRecord.fromMap).toList();
    out.sort((a, b) => b.ts.compareTo(a.ts)); // свежее сверху
    return out;
  }

  static Future<void> save(List<BPRecord> items) async {
    items.sort((a, b) => b.ts.compareTo(a.ts));
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((e) => e.toMap()).toList());
    await sp.setString(_key, raw);
  }
}

/// ====== Уведомления ======
class _Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> ensureInit() async {
    if (_inited) return;
    final android = const AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    try {
      tz.initializeTimeZones();
      final name = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _inited = true;
  }

  static Future<int> scheduleDaily(TimeOfDay tod) async {
    await ensureInit();
    final id = DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, tod.hour, tod.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id,
      'Напоминание',
      'Пора измерить давление',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails('bp_logger_ch', 'BP Logger'),
      ),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return id;
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);

  static Future<void> cancelAll() => _plugin.cancelAll();
}

/// ====== Главный экран ======
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum PeriodPreset { d1, d7, d30, custom }

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  final _note = TextEditingController();
  DateTime _picked = DateTime.now();

  List<BPRecord> _all = [];
  List<int> _reminderIds = []; // id уведомлений

  // фильтр
  PeriodPreset _preset = PeriodPreset.d7;
  DateTimeRange? _custom;

  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final list = await BPStore.load();
    final sp = await SharedPreferences.getInstance();
    _reminderIds = sp.getStringList('reminders')?.map(int.parse).toList() ?? [];
    setState(() => _all = list);
  }

  Future<void> _saveReminders() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('reminders', _reminderIds.map((e) => e.toString()).toList());
  }

  List<BPRecord> get _filtered {
    final now = DateTime.now();
    DateTime from;
    DateTime to;
    switch (_preset) {
      case PeriodPreset.d1:
        from = now.subtract(const Duration(days: 1));
        to = now;
        break;
      case PeriodPreset.d7:
        from = now.subtract(const Duration(days: 7));
        to = now;
        break;
      case PeriodPreset.d30:
        from = now.subtract(const Duration(days: 30));
        to = now;
        break;
      case PeriodPreset.custom:
        final r = _custom ??
            DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
        from = r.start;
        to = r.end;
        break;
    }
    return _all.where((e) => !e.ts.isBefore(from) && !e.ts.isAfter(to)).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
  }

  Future<void> _pickCustomRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _custom ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      locale: const Locale('ru', 'RU'),
    );
    if (r != null) {
      setState(() {
        _preset = PeriodPreset.custom;
        _custom = r;
      });
    }
  }

  Future<void> _add() async {
    final sys = int.tryParse(_sys.text.trim());
    final dia = int.tryParse(_dia.text.trim());
    final pulse = _pulse.text.trim().isEmpty ? null : int.tryParse(_pulse.text.trim());
    if (sys == null || dia == null) {
      _snack('Укажи SYS и DIA');
      return;
    }
    final item = BPRecord(ts: _picked, sys: sys, dia: dia, pulse: pulse, note: _note.text.trim().isEmpty ? null : _note.text.trim());
    final list = List<BPRecord>.from(_all)..add(item);
    await BPStore.save(list);
    setState(() {
      _all = list;
      _sys.clear();
      _dia.clear();
      _pulse.clear();
      _note.clear();
      _picked = DateTime.now();
    });
  }

  Future<void> _delete(BPRecord r) async {
    final list = List<BPRecord>.from(_all)..removeWhere((e) => e.ts == r.ts && e.sys == r.sys && e.dia == r.dia && e.pulse == r.pulse && e.note == r.note);
    await BPStore.save(list);
    setState(() => _all = list);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _showAverages() {
    final data = _filtered;
    if (data.isEmpty) {
      _snack('Нет данных в выбранном периоде');
      return;
    }
    final avgSys = (data.map((e) => e.sys).reduce((a, b) => a + b) / data.length).toStringAsFixed(0);
    final avgDia = (data.map((e) => e.dia).reduce((a, b) => a + b) / data.length).toStringAsFixed(0);
    final hasPulse = data.any((e) => e.pulse != null);
    final avgPulse = hasPulse
        ? (data.where((e) => e.pulse != null).map((e) => e.pulse!).reduce((a, b) => a + b) /
                data.where((e) => e.pulse != null).length)
            .toStringAsFixed(0)
        : '—';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Средние за период', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text('SYS: $avgSys   DIA: $avgDia   Pulse: $avgPulse'),
          const SizedBox(height: 8),
          Text('Записей: ${data.length}'),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<void> _exportCsvShare() async {
    final dfDate = DateFormat('yyyy-MM-dd HH:mm');
    final rows = <String>['timestamp,sys,dia,pulse,note'];
    for (final r in _filtered.reversed) {
      final line =
          '${dfDate.format(r.ts)},${r.sys},${r.dia},${r.pulse ?? ""},"${(r.note ?? "").replaceAll('"', '""')}"';
      rows.add(line);
    }
    final csv = rows.join('\n');
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final xfile = XFile.fromData(bytes,
        mimeType: 'text/csv', name: 'bp_${DateTime.now().millisecondsSinceEpoch}.csv');
    await Share.shareXFiles([xfile], text: 'Экспорт давления (выбранный период)');
  }

  Future<void> _addReminder() async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (t == null) return;
    final id = await _Notifications.scheduleDaily(t);
    setState(() => _reminderIds.add(id));
    await _saveReminders();
    _snack('Напоминание добавлено: ${t.format(context)} ежедневно');
  }

  Future<void> _clearReminders() async {
    await _Notifications.cancelAll();
    setState(() => _reminderIds.clear());
    await _saveReminders();
    _snack('Все напоминания удалены');
  }

  String _periodLabel() {
    switch (_preset) {
      case PeriodPreset.d1:
        return '24 часа';
      case PeriodPreset.d7:
        return '7 дней';
      case PeriodPreset.d30:
        return '30 дней';
      case PeriodPreset.custom:
        final r = _custom!;
        return '${DateFormat('dd.MM').format(r.start)}–${DateFormat('dd.MM').format(r.end)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Logger+'),
        actions: [
          IconButton(
            tooltip: 'Экспорт CSV',
            onPressed: _exportCsvShare,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Фильтр',
            onSelected: (v) {
              if (v == 'custom') {
                _pickCustomRange();
              } else {
                setState(() => _preset = {
                      'd1': PeriodPreset.d1,
                      'd7': PeriodPreset.d7,
                      'd30': PeriodPreset.d30,
                    }[v]!);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'd1', child: Text('24 часа')),
              const PopupMenuItem(value: 'd7', child: Text('7 дней')),
              const PopupMenuItem(value: 'd30', child: Text('30 дней')),
              const PopupMenuItem(value: 'custom', child: Text('Выбрать период…')),
            ],
            icon: const Icon(Icons.filter_alt_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Список'), Tab(text: 'Графики')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ======== Список / Ввод ========
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _inputCard(df),
                const SizedBox(height: 12),
                _periodChips(),
                const SizedBox(height: 8),
                if (_filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Нет записей в выбранном периоде'),
                  ),
                ..._filtered.map((r) => Card(
                      child: ListTile(
                        title: Text('${r.sys}/${r.dia}  ${r.pulse != null ? ' • ${r.pulse} bpm' : ''}'),
                        subtitle: Text(df.format(r.ts) + (r.note?.isNotEmpty == true ? '\n${r.note}' : '')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(r),
                        ),
                      ),
                    )),
                const SizedBox(height: 84),
              ],
            ),
          ),
          // ======== Графики ========
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _chartCard('Систолическое (SYS)', _filtered, (r) => r.sys),
                const SizedBox(height: 12),
                _chartCard('Диастолическое (DIA)', _filtered, (r) => r.dia),
                if (_filtered.any((e) => e.pulse != null)) ...[
                  const SizedBox(height: 12),
                  _chartCard('Пульс', _filtered.where((e) => e.pulse != null).toList(), (r) => r.pulse!),
                ],
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Сохранить'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Средние за период',
                onPressed: _showAverages,
                icon: const Icon(Icons.functions_rounded),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Напоминания',
                onSelected: (v) {
                  if (v == 'add') _addReminder();
                  if (v == 'clear') _clearReminders();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'add',
                    child: Row(children: const [Icon(Icons.alarm_add_outlined), SizedBox(width: 8), Text('Добавить напоминание')]),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(children: const [Icon(Icons.alarm_off_outlined), SizedBox(width: 8), Text('Удалить все напоминания')]),
                  ),
                ],
                icon: const Icon(Icons.alarm_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputCard(DateFormat df) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _sys,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SYS'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dia,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'DIA'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pulse,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Пульс (необязательно)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'Примечание (необязательно)'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _picked,
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('ru', 'RU'),
                    );
                    if (d == null) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_picked),
                    );
                    if (t == null) return;
                    setState(() => _picked = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: Text(DateFormat('yyyy-MM-dd HH:mm').format(_picked)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodChips() {
    return Row(
      children: [
        ChoiceChip(
          selected: _preset == PeriodPreset.d1,
          label: const Text('24 часа'),
          onSelected: (_) => setState(() => _preset = PeriodPreset.d1),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          selected: _preset == PeriodPreset.d7,
          label: const Text('7 дней'),
          onSelected: (_) => setState(() => _preset = PeriodPreset.d7),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          selected: _preset == PeriodPreset.d30,
          label: const Text('30 дней'),
          onSelected: (_) => setState(() => _preset = PeriodPreset.d30),
        ),
        const SizedBox(width: 8),
        ActionChip(
          label: Text('Период: ${_periodLabel()}'),
          onPressed: _pickCustomRange,
        ),
      ],
    );
  }

  Widget _chartCard(String title, List<BPRecord> list, int Function(BPRecord) getY) {
    if (list.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [Text('$title — нет данных')]),
        ),
      );
    }
    final xs = list.map((e) => e.ts.millisecondsSinceEpoch.toDouble()).toList();
    final ys = list.map(getY).map((e) => e.toDouble()).toList();

    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b) - 5;
    final maxY = ys.reduce((a, b) => a > b ? a : b) + 5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: false,
                      spots: [
                        for (var i = 0; i < list.length; i++)
                          FlSpot(xs[i], ys[i]),
                      ],
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                    )
                  ],
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final d = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Text(DateFormat('MM-dd').format(d), style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
