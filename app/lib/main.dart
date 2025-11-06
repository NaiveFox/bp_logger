import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BpApp());
}

class BpApp extends StatelessWidget {
  const BpApp({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF3C7BEA),
      textTheme: GoogleFonts.interTextTheme(),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BP Logger+',
      theme: theme,
      home: const HomeScreen(),
    );
  }
}

class Measurement {
  final DateTime ts;
  final int sys;
  final int dia;
  final int pulse;

  Measurement({
    required this.ts,
    required this.sys,
    required this.dia,
    required this.pulse,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts.toIso8601String(),
        'sys': sys,
        'dia': dia,
        'pulse': pulse,
      };

  static Measurement fromJson(Map<String, dynamic> j) => Measurement(
        ts: DateTime.parse(j['ts'] as String),
        sys: j['sys'] as int,
        dia: j['dia'] as int,
        pulse: j['pulse'] as int,
      );
}

enum Period { h24, d7, d30, custom }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DateFormat dFmt = DateFormat('dd.MM.yy');
  final DateFormat tFmt = DateFormat('HH:mm');

  List<Measurement> _items = [];
  bool _notifEnabled = false;
  TimeOfDay _notifTime = const TimeOfDay(hour: 9, minute: 0);

  Period _period = Period.h24;
  DateTimeRange? _customRange;

  final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadAll();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _fln.initialize(const InitializationSettings(android: androidInit));
    // Пробуем запросить разрешения (Android 13+)
    final androidImpl =
        _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  Future<void> _loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('records');
    final notifOn = sp.getBool('notif_on') ?? false;
    final notifHour = sp.getInt('notif_h') ?? 9;
    final notifMin = sp.getInt('notif_m') ?? 0;

    List<Measurement> items = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        items = list.map(Measurement.fromJson).toList();
      } catch (_) {}
    }
    setState(() {
      _items = items..sort((a, b) => a.ts.compareTo(b.ts));
      _notifEnabled = notifOn;
      _notifTime = TimeOfDay(hour: notifHour, minute: notifMin);
    });
    if (_notifEnabled) {
      await _scheduleDaily(_notifTime);
    } else {
      await _fln.cancel(1001);
    }
  }

  Future<void> _saveAll() async {
    final sp = await SharedPreferences.getInstance();
    final data = jsonEncode(_items.map((e) => e.toJson()).toList());
    await sp.setString('records', data);
  }

  Future<void> _toggleNotifications(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('notif_on', v);
    setState(() => _notifEnabled = v);
    if (v) {
      await _scheduleDaily(_notifTime);
    } else {
      await _fln.cancel(1001);
    }
  }

  Future<void> _pickNotifTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _notifTime);
    if (picked != null) {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('notif_h', picked.hour);
      await sp.setInt('notif_m', picked.minute);
      setState(() => _notifTime = picked);
      if (_notifEnabled) {
        await _scheduleDaily(_notifTime);
      }
    }
  }

  Future<void> _scheduleDaily(TimeOfDay t) async {
    final now = DateTime.now();
    final dtToday = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    final next =
        dtToday.isAfter(now) ? dtToday : dtToday.add(const Duration(days: 1));
    await _fln.zonedSchedule(
      1001,
      'Пора измерить давление',
      'Запиши показания — это займёт 10 секунд',
      tz.TZDateTime.from(next, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bp_daily',
          'Ежедневные напоминания',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _addNow() async {
    final rec = await _showAddDialog(initialTs: DateTime.now());
    if (rec != null) {
      setState(() {
        _items.add(rec);
        _items.sort((a, b) => a.ts.compareTo(b.ts));
      });
      await _saveAll();
    }
  }

  Future<void> _addBackDated() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
      helpText: 'Выбери дату',
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Выбери время',
    );
    if (time == null) return;
    final ts =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final rec = await _showAddDialog(initialTs: ts);
    if (rec != null) {
      setState(() {
        _items.add(rec);
        _items.sort((a, b) => a.ts.compareTo(b.ts));
      });
      await _saveAll();
    }
  }

  Future<Measurement?> _showAddDialog({required DateTime initialTs}) async {
    final sysCtrl = TextEditingController();
    final diaCtrl = TextEditingController();
    final pulCtrl = TextEditingController();

    return showDialog<Measurement>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Новые показания'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LabeledField(label: 'SYS (верхнее)', controller: sysCtrl),
              const SizedBox(height: 8),
              _LabeledField(label: 'DIA (нижнее)', controller: diaCtrl),
              const SizedBox(height: 8),
              _LabeledField(label: 'PULSE (пульс)', controller: pulCtrl),
              const SizedBox(height: 8),
              Text(
                'Время: ${dFmt.format(initialTs)}, ${tFmt.format(initialTs)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final s = int.tryParse(sysCtrl.text.trim());
                final d = int.tryParse(diaCtrl.text.trim());
                final p = int.tryParse(pulCtrl.text.trim());
                if (s == null || d == null || p == null) return;
                Navigator.pop(
                  ctx,
                  Measurement(ts: initialTs, sys: s, dia: d, pulse: p),
                );
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  List<Measurement> _filtered() {
    final now = DateTime.now();
    DateTime from;
    switch (_period) {
      case Period.h24:
        from = now.subtract(const Duration(hours: 24));
        break;
      case Period.d7:
        from = now.subtract(const Duration(days: 7));
        break;
      case Period.d30:
        from = now.subtract(const Duration(days: 30));
        break;
      case Period.custom:
        if (_customRange == null) return _items;
        from = _customRange!.start;
        break;
    }
    final to = _period == Period.custom && _customRange != null
        ? _customRange!.end
        : now;
    return _items.where((e) => e.ts.isAfter(from) && e.ts.isBefore(to)).toList();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      helpText: 'Выбери период',
    );
    if (picked != null) {
      setState(() {
        _period = Period.custom;
        _customRange = picked;
      });
    }
  }

  Future<void> _share() async {
    final list = _filtered();
    if (list.isEmpty) return;

    final buf = StringBuffer();
    final String title;
    switch (_period) {
      case Period.h24:
        title = 'Последние 24 часа';
        break;
      case Period.d7:
        title = 'Последние 7 дней';
        break;
      case Period.d30:
        title = 'Последние 30 дней';
        break;
      case Period.custom:
        final s = dFmt.format(_customRange!.start);
        final e = dFmt.format(_customRange!.end);
        title = 'Период: $s — $e';
        break;
    }

    buf.writeln('BP Logger+ — $title');
    buf.writeln('Дата; Время; SYS; DIA; PULSE');

    for (final m in list) {
      buf.writeln(
          '${dFmt.format(m.ts)}; ${tFmt.format(m.ts)}; ${m.sys}; ${m.dia}; ${m.pulse}');
    }

    await Share.share(buf.toString(), subject: 'Показания давления — $title');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Logger+'),
        actions: [
          IconButton(
            tooltip: 'Поделиться',
            onPressed: _share,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Большая основная кнопка
          FilledButton.tonal(
            onPressed: _addNow,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            child: const Text('Записать сейчас'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _addBackDated,
            child: const Text('Записать задним числом'),
          ),
          const SizedBox(height: 16),

          // Напоминания
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Напоминания'),
                        const SizedBox(height: 4),
                        Text(
                          _notifEnabled
                              ? 'Ежедневно в ${_notifTime.format(context)}'
                              : 'Выключены',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(value: _notifEnabled, onChanged: _toggleNotifications),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Время напоминания',
                    onPressed: _pickNotifTime,
                    icon: const Icon(Icons.schedule),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Выбор периода
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('24ч'),
                selected: _period == Period.h24,
                onSelected: (_) => setState(() => _period = Period.h24),
              ),
              ChoiceChip(
                label: const Text('7 дней'),
                selected: _period == Period.d7,
                onSelected: (_) => setState(() => _period = Period.d7),
              ),
              ChoiceChip(
                label: const Text('30 дней'),
                selected: _period == Period.d30,
                onSelected: (_) => setState(() => _period = Period.d30),
              ),
              ActionChip(
                label: const Text('Период…'),
                onPressed: _pickCustomRange,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // График
          if (filtered.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Нет данных за выбранный период'),
            ))
          else
            SizedBox(
              height: 260,
              child: LineChart(_buildChartData(filtered)),
            ),

          const SizedBox(height: 16),

          // Таблица последних записей
          Text('Последние записи',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...filtered.reversed.take(10).map((m) => ListTile(
                dense: true,
                leading: const Icon(Icons.favorite_border),
                title:
                    Text('${m.sys}/${m.dia}  ·  ${m.pulse} уд/мин'),
                subtitle: Text(
                    '${dFmt.format(m.ts)}, ${tFmt.format(m.ts)}'),
              )),
        ],
      ),
    );
  }

  LineChartData _buildChartData(List<Measurement> list) {
    // Превращаем в точки: X = индекс (слева направо), Y — значения
    final spotsSys = <FlSpot>[];
    final spotsDia = <FlSpot>[];
    final spotsPul = <FlSpot>[];

    for (var i = 0; i < list.length; i++) {
      spotsSys.add(FlSpot(i.toDouble(), list[i].sys.toDouble()));
      spotsDia.add(FlSpot(i.toDouble(), list[i].dia.toDouble()));
      spotsPul.add(FlSpot(i.toDouble(), list[i].pulse.toDouble()));
    }

    String bottomTitle(double x) {
      final idx = x.round().clamp(0, list.length - 1);
      final ts = list[idx].ts;
      // Если в пределах суток — показываем время, иначе дату
      final isSameDay = ts.isAfter(DateTime.now().subtract(const Duration(hours: 24)));
      return isSameDay ? tFmt.format(ts) : dFmt.format(ts);
    }

    return LineChartData(
      minX: 0,
      maxX: (list.length - 1).toDouble(),
      lineTouchData: const LineTouchData(enabled: true),
      gridData: const FlGridData(show: true),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 36),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (list.length / 6).clamp(1, 6).toDouble(),
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  bottomTitle(value),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spotsSys,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: spotsDia,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: spotsPul,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _LabeledField({required this.label, required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
