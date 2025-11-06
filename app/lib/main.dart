import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6D4DCF));
    return MaterialApp(
      title: 'BP Logger+',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const Home(),
    );
  }
}

class Record {
  final DateTime ts;
  final int sys;
  final int dia;
  final int? pulse;
  final String? note;
  Record(this.ts, this.sys, this.dia, this.pulse, this.note);
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final List<Record> _items = [];
  late final TabController _tabs;
  // notifications
  final _notifs = FlutterLocalNotificationsPlugin();
  TimeOfDay? _reminderTime;
  bool _reminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifs.initialize(const InitializationSettings(android: android));
    if (Platform.isAndroid) {
      final androidSpecifics = await _notifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidSpecifics?.requestNotificationsPermission();
    }
  }

  Future<void> _scheduleDaily(TimeOfDay time) async {
    _reminderTime = time;
    _reminderEnabled = true;
    final now = DateTime.now();
    final tzLoc = tz.getLocation(DateTime.now().timeZoneName);
    final first = DateTime(
        now.year, now.month, now.day, time.hour, time.minute);
    final firstTz = tz.TZDateTime.from(
        first.isBefore(now) ? first.add(const Duration(days: 1)) : first, tzLoc);
    await _notifs.zonedSchedule(
      1001,
      'BP Logger+',
      'Пора записать давление',
      firstTz,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bp_daily', 'Daily Reminder',
          importance: Importance.max, priority: Priority.high)),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    setState(() {});
  }

  Future<void> _cancelDaily() async {
    await _notifs.cancel(1001);
    _reminderEnabled = false;
    _reminderTime = null;
    setState(() {});
  }

  // --- UI helpers
  String _fmt(DateTime d) => DateFormat('dd.MM.yyyy, HH:mm').format(d);

  Future<void> _addNow() async {
    final r = await showDialog<Record>(
      context: context,
      builder: (_) => _RecordDialog(initial: DateTime.now()),
    );
    if (r != null) setState(() => _items.add(r));
  }

  Future<void> _addBackdate() async {
    final r = await showDialog<Record>(
      context: context,
      builder: (_) => _RecordDialog(backdate: true, initial: DateTime.now()),
    );
    if (r != null) setState(() => _items.add(r));
  }

  // export: CSV и markdown-таблица
  Future<void> _share() async {
    final period = await _pickPeriod(context);
    if (period == null) return;
    final from = period.$1, to = period.$2;
    final data = _items
        .where((e) => !e.ts.isBefore(from) && !e.ts.isAfter(to))
        .toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));

    final csvHeader = "timestamp;date;time;sys;dia;pulse;note";
    final csvRows = data.map((e) {
      final date = DateFormat('dd.MM.yyyy').format(e.ts);
      final time = DateFormat('HH:mm').format(e.ts);
      return "${e.ts.toIso8601String()};$date;$time;${e.sys};${e.dia};${e.pulse ?? ""};\"${e.note ?? ""}\"";
    }).join("\n");

    final pretty = StringBuffer()
      ..writeln(
          "BP Logger+ — экспорт за период ${_fmt(from)} — ${_fmt(to)}")
      ..writeln("| Дата | Время | SYS | DIA | Пульс |")
      ..writeln("|---|---:|---:|---:|---:|");
    for (final e in data) {
      pretty.writeln(
          "| ${DateFormat('dd.MM.yyyy').format(e.ts)} | ${DateFormat('HH:mm').format(e.ts)} | ${e.sys} | ${e.dia} | ${e.pulse ?? ''} |");
    }

    final dir = Directory.systemTemp;
    final csvFile = File("${dir.path}/bp_export.csv");
    final mdFile = File("${dir.path}/bp_export.md");
    await csvFile.writeAsString("$csvHeader\n$csvRows");
    await mdFile.writeAsString(pretty.toString());

    await Share.shareXFiles([
      XFile(csvFile.path, name: "bp_export.csv"),
      XFile(mdFile.path, name: "bp_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.md"),
    ]);
  }

  Future<(DateTime, DateTime)?> _pickPeriod(BuildContext ctx) async {
    final now = DateTime.now();
    DateTime from = now.subtract(const Duration(days: 7));
    DateTime to = now;
    return await showDialog<(DateTime, DateTime)>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text("Период для экспорта/графика"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                OutlinedButton(onPressed: () {
                  from = now.subtract(const Duration(days:7)); to = now;
                  Navigator.pop(ctx, (from, to));
                }, child: const Text("7 дней")),
                OutlinedButton(onPressed: () {
                  from = now.subtract(const Duration(days:30)); to = now;
                  Navigator.pop(ctx, (from, to));
                }, child: const Text("30 дней")),
                OutlinedButton(onPressed: () async {
                  final df = await showDatePicker(context: ctx,
                    firstDate: DateTime(2020), lastDate: now, initialDate: from);
                  if (df == null) return;
                  final dt = await showDatePicker(context: ctx,
                    firstDate: DateTime(2020), lastDate: now, initialDate: to);
                  if (dt == null) return;
                  Navigator.pop(ctx, (DateTime(df.year,df.month,df.day), DateTime(dt.year,dt.month,dt.day,23,59)));
                }, child: const Text("Выбрать…")),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ["Запись", "Графики", "Напоминания"];
    return Scaffold(
      appBar: AppBar(
        title: const Text("BP Logger+"),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share), onPressed: _share),
        ],
        bottom: TabBar(controller: _tabs, tabs: [
          for (final t in tabs) Tab(text: t),
        ]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildInputTab(),
          _buildChartsTab(),
          _buildRemindersTab(),
        ],
      ),
      floatingActionButton: _tabs.index == 0 ? _fab() : null,
    );
  }

  Widget _fab() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _addNow,
            icon: const Icon(Icons.add),
            label: const Text("Записать сейчас"),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _addBackdate,
            icon: const Icon(Icons.schedule),
            label: const Text("За другую дату/время"),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          ),
        ],
      );

  Widget _buildInputTab() {
    if (_items.isEmpty) {
      return Center(
        child: Text("Пока записей нет. Жми «Записать сейчас».",
            style: Theme.of(context).textTheme.titleMedium),
      );
    }
    final items = _items..sort((a,b)=>b.ts.compareTo(a.ts));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, i) {
        final e = items[i];
        return ListTile(
          title: Text("${e.sys}/${e.dia}  ${e.pulse!=null? '• ${e.pulse} bpm':''}"),
          subtitle: Text(_fmt(e.ts)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () { setState(()=>_items.remove(e)); },
          ),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemCount: items.length,
    );
  }

  Widget _buildChartsTab() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 7));
    final view = _items.where((e) => e.ts.isAfter(from)).toList()
      ..sort((a,b)=>a.ts.compareTo(b.ts));

    if (view.isEmpty) {
      return Center(child: Text("Нет данных за последние 7 дней"));
    }

    List<FlSpot> sSys = [], sDia = [], sPulse = [];
    final base = view.first.ts.millisecondsSinceEpoch.toDouble();
    for (final e in view) {
      final x = (e.ts.millisecondsSinceEpoch - base) / (1000*60*60); // часы
      sSys.add(FlSpot(x, e.sys.toDouble()));
      sDia.add(FlSpot(x, e.dia.toDouble()));
      if (e.pulse != null) sPulse.add(FlSpot(x, e.pulse!.toDouble()));
    }

    String fmtX(double x) {
      final dt = DateTime.fromMillisecondsSinceEpoch((x*3600000).toInt() + base.toInt());
      return DateFormat('dd.MM HH:mm').format(dt);
    }

    Widget line(List<FlSpot> data, String name) {
      return LineChart(
        LineChartData(
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta){
              return Transform.rotate(
                angle: -0.6,
                child: Text(fmtX(v), style: const TextStyle(fontSize: 10)),
              );
            })),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true),
          lineBarsData: [
            LineChartBarData(spots: data, isCurved: true, dotData: const FlDotData(show: true)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Text("Систолическое (SYS)", style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 220, child: line(sSys, "SYS")),
          const SizedBox(height: 16),
          Text("Диастолическое (DIA)", style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 220, child: line(sDia, "DIA")),
          const SizedBox(height: 16),
          Text("Пульс", style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 220, child: line(sPulse, "Pulse")),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final p = await _pickPeriod(context);
              if (p == null) return;
              setState(() {}); // в MVP просто перерисуем
            },
            icon: const Icon(Icons.timeline),
            label: const Text("Выбрать период для графиков"),
          )
        ],
      ),
    );
  }

  Widget _buildRemindersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text("Ежедневное напоминание"),
            subtitle: Text(_reminderEnabled
                ? "Время: ${_reminderTime?.format(context) ?? '--:--'}"
                : "Выключено"),
            value: _reminderEnabled,
            onChanged: (v) async {
              if (v) {
                final t = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 10, minute: 0),
                  builder: (ctx, child) => MediaQuery(
                    data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                );
                if (t != null) await _scheduleDaily(t);
              } else {
                await _cancelDaily();
              }
            },
          ),
          const SizedBox(height: 8),
          if (_reminderEnabled)
            OutlinedButton.icon(
              onPressed: _cancelDaily,
              icon: const Icon(Icons.delete_outline),
              label: const Text("Удалить напоминание"),
            ),
        ],
      ),
    );
  }
}

class _RecordDialog extends StatefulWidget {
  final bool backdate;
  final DateTime initial;
  const _RecordDialog({required this.initial, this.backdate=false});
  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late DateTime ts;
  final sys = TextEditingController();
  final dia = TextEditingController();
  final pulse = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    ts = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.backdate ? "Запись за другую дату" : "Записать сейчас"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.backdate)
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDate: ts,
                    );
                    if (d != null) setState(() => ts = DateTime(d.year,d.month,d.day,ts.hour,ts.minute));
                  },
                  child: Text(DateFormat('dd.MM.yyyy').format(ts)),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(ts),
                      builder: (ctx, child) => MediaQuery(
                        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                        child: child!,
                      ),
                    );
                    if (t != null) setState(() => ts = DateTime(ts.year,ts.month,ts.day,t.hour,t.minute));
                  },
                  child: Text(DateFormat('HH:mm').format(ts)),
                )),
              ]),
            const SizedBox(height: 8),
            _num(sys, "SYS", "120"),
            const SizedBox(height: 8),
            _num(dia, "DIA", "80"),
            const SizedBox(height: 8),
            _num(pulse, "Пульс (по жел.)", "70", optional: true),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: "Заметка (опционально)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("Отмена")),
        FilledButton(
          onPressed: () {
            final s = int.tryParse(sys.text);
            final d = int.tryParse(dia.text);
            final p = pulse.text.isEmpty ? null : int.tryParse(pulse.text);
            if (s==null || d==null) return;
            Navigator.pop(context, Record(ts, s, d, p, note.text.isEmpty? null : note.text));
          },
          child: const Text("Сохранить"),
        )
      ],
    );
  }

  Widget _num(TextEditingController c, String label, String hint, {bool optional=false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixText: optional ? "опц." : null,
      ),
    );
  }
}
