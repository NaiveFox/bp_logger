import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

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
      title: 'BP Logger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      home: const HomeScreen(),
    );
  }
}

// ====== Модель и БД ======
class Measurement {
  final int? id;
  final int sys, dia, pulse;
  final DateTime ts;
  Measurement({this.id, required this.sys, required this.dia, required this.pulse, required this.ts});
  Map<String, dynamic> toMap() => {
        'id': id,
        'systolic': sys,
        'diastolic': dia,
        'pulse': pulse,
        'ts_utc': ts.toUtc().millisecondsSinceEpoch,
      };
  static Measurement fromMap(Map<String, dynamic> m) => Measurement(
        id: m['id'] as int?,
        sys: m['systolic'] as int,
        dia: m['diastolic'] as int,
        pulse: m['pulse'] as int,
        ts: DateTime.fromMillisecondsSinceEpoch(m['ts_utc'], isUtc: true).toLocal(),
      );
}

class DB {
  static Database? _db;
  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final file = p.join(dbPath, 'bp_logger.db');
    _db = await openDatabase(file, version: 1, onCreate: (db, v) async {
      await db.execute('''
      CREATE TABLE measurements(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        systolic INTEGER NOT NULL,
        diastolic INTEGER NOT NULL,
        pulse INTEGER NOT NULL,
        ts_utc INTEGER NOT NULL
      );
      ''');
      await db.execute('CREATE INDEX idx_ts ON measurements(ts_utc DESC);');
    });
    return _db!;
  }
  static Future<int> insert(Measurement m) async {
    final db = await instance;
    return db.insert('measurements', m.toMap()..remove('id'));
  }
  static Future<List<Measurement>> recent({int days = 14}) async {
    final db = await instance;
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await db.query('measurements',
        where: 'ts_utc >= ?', whereArgs: [cutoff], orderBy: 'ts_utc ASC');
    return rows.map(Measurement.fromMap).toList();
  }
  static Future<List<Measurement>> all() async {
    final db = await instance;
    final rows = await db.query('measurements', orderBy: 'ts_utc DESC');
    return rows.map(Measurement.fromMap).toList();
  }
}

// ====== Уведомления ======
class _Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> ensureInit() async {
    if (_inited) return;
    tz.initializeTimeZones();
    try {
      final name = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));
    _inited = true;
  }

  static Future<void> scheduleDaily(int id, TimeOfDay time, {String title = 'BP напоминание', String body = 'Замерить давление'}) async {
    final now = tz.TZDateTime.now(tz.local);
    final next = _nextInstance(time, now);
    await _plugin.zonedSchedule(
      id, title, body, next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bp_channel','BP Reminders',
          channelDescription: 'Ежедневные напоминания о замере давления',
          importance: Importance.high, priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
  static Future<void> cancel(int id) => _plugin.cancel(id);

  static tz.TZDateTime _nextInstance(TimeOfDay t, tz.TZDateTime from) {
    var scheduled = tz.TZDateTime(tz.local, from.year, from.month, from.day, t.hour, t.minute);
    if (scheduled.isBefore(from)) scheduled = scheduled.add(const Duration(days: 1));
    return scheduled;
  }
}

// ====== Экспорт ======
class Exporter {
  static Future<File> exportCsv(List<Measurement> list) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, 'bp_export.csv'));
    final b = StringBuffer('date,sys,dia,pulse\n');
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    for (final m in list) {
      b.writeln('${fmt.format(m.ts)},${m.sys},${m.dia},${m.pulse}');
    }
    await f.writeAsString(b.toString());
    return f;
  }

  static Future<File> exportPdf(List<Measurement> list) async {
    final pdf = pw.Document();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    final sysSeries = <pw.LineData>[];
    final diaSeries = <pw.LineData>[];
    for (int i = 0; i < list.length; i++) {
      sysSeries.add(pw.LineData(i.toDouble(), list[i].sys.toDouble()));
      diaSeries.add(pw.LineData(i.toDouble(), list[i].dia.toDouble()));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          pw.Text('Отчёт по артериальному давлению', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Экспортировано: ${fmt.format(DateTime.now())}'),
          pw.SizedBox(height: 16),
          if (list.isNotEmpty)
            pw.Container(
              height: 160,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
              child: pw.Chart(
                grid: pw.CartesianGrid(
                  xAxis: pw.FixedAxis<List<double>>(
                    [for (int i = 0; i < math.max(list.length, 6); i++) i.toDouble()],
                    format: (v) => v.toInt().toString(),
                  ),
                  yAxis: pw.FixedAxis<List<double>>([40,80,120,160,200].map((e)=>e.toDouble()).toList(),
                    format: (v) => v.toInt().toString(),
                  ),
                ),
                datasets: [
                  pw.LineDataSet(sysSeries, drawSurface: false, isCurved: true, color: PdfColors.blue),
                  pw.LineDataSet(diaSeries, drawSurface: false, isCurved: true, color: PdfColors.red),
                ],
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FixedColumnWidth(140),
              1: const pw.FixedColumnWidth(60),
              2: const pw.FixedColumnWidth(60),
              3: const pw.FixedColumnWidth(60),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('Дата/время', b: true), _cell('SYS', b: true),
                  _cell('DIA', b: true), _cell('Пульс', b: true),
                ],
              ),
              ...list.map((m) => pw.TableRow(children: [
                    _cell(fmt.format(m.ts)),
                    _cell('${m.sys}'),
                    _cell('${m.dia}'),
                    _cell('${m.pulse}'),
                  ])),
            ],
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, 'bp_report.pdf'));
    await f.writeAsBytes(await pdf.save());
    return f;
  }

  static pw.Widget _cell(String t, {bool b = false}) =>
      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(t, style: pw.TextStyle(fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal)));
}

// ====== UI ======
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final sysC = TextEditingController();
  final diaC = TextEditingController();
  final pulseC = TextEditingController();

  List<Measurement> _recent = [];
  List<Measurement> _all = [];
  bool _remMorningOn = false;
  bool _remEveningOn = false;
  TimeOfDay _morning = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _evening = const TimeOfDay(hour: 21, minute: 0);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _recent = await DB.recent(days: 14);
    _all = await DB.all();
    if (mounted) setState(() {});
  }

  Color _zoneColor(Measurement m) {
    if (m.sys < 120 && m.dia < 80) return Colors.green;
    if (m.sys < 140 && m.dia < 90) return Colors.orange;
    return Colors.red;
  }

  Future<void> _add() async {
    final sys = int.tryParse(sysC.text);
    final dia = int.tryParse(diaC.text);
    final pulse = int.tryParse(pulseC.text);
    if (sys == null || dia == null || pulse == null) return;
    await DB.insert(Measurement(sys: sys, dia: dia, pulse: pulse, ts: DateTime.now()));
    sysC.clear(); diaC.clear(); pulseC.clear();
    await _reload();
  }

  Future<void> _exportCsv() async {
    final f = await Exporter.exportCsv(await DB.all());
    await Share.shareXFiles([XFile(f.path)], text: 'BP export (CSV)');
  }

  Future<void> _exportPdf() async {
    final f = await Exporter.exportPdf(await DB.all());
    await Share.shareXFiles([XFile(f.path)], text: 'BP report (PDF)');
  }

  Future<void> _pickTime(bool morning) async {
    final initial = morning ? _morning : _evening;
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t == null) return;
    setState(() {
      if (morning) _morning = t; else _evening = t;
    });
    if (morning && _remMorningOn) {
      await _Notifications.scheduleDaily(10, _morning, title: 'Утро', body: 'Измерь давление');
    }
    if (!morning && _remEveningOn) {
      await _Notifications.scheduleDaily(20, _evening, title: 'Вечер', body: 'Измерь давление');
    }
  }

  Future<void> _toggleMorning(bool v) async {
    setState(() => _remMorningOn = v);
    if (v) {
      await _Notifications.scheduleDaily(10, _morning, title: 'Утро', body: 'Измерь давление');
    } else {
      await _Notifications.cancel(10);
    }
  }

  Future<void> _toggleEvening(bool v) async {
    setState(() => _remEveningOn = v);
    if (v) {
      await _Notifications.scheduleDaily(20, _evening, title: 'Вечер', body: 'Измерь давление');
    } else {
      await _Notifications.cancel(20);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineSys = _recent.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.sys.toDouble())).toList();
    final lineDia = _recent.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.dia.toDouble())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Logger'),
        actions: [
          IconButton(onPressed: _exportCsv, tooltip: 'Экспорт CSV', icon: const Icon(Icons.table_view)),
          IconButton(onPressed: _exportPdf, tooltip: 'Экспорт PDF', icon: const Icon(Icons.picture_as_pdf)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Новая запись', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: sysC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SYS'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: diaC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DIA'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: pulseC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Пульс'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _add, child: const Text('OK')),
          ]),
          const SizedBox(height: 16),
          const Text('График (14 дней)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: LineChart(LineChartData(
              minY: 40, maxY: 200,
              gridData: const FlGridData(show: true, drawHorizontalLine: true, drawVerticalLine: false),
              titlesData: const FlTitlesData(bottomTitles: AxisTitles(), rightTitles: AxisTitles(), topTitles: AxisTitles()),
              lineBarsData: [
                LineChartBarData(spots: lineSys, isCurved: true, dotData: const FlDotData(show: false)),
                LineChartBarData(spots: lineDia, isCurved: true, dotData: const FlDotData(show: false)),
              ],
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(y: 120, dashArray: [8,4], color: Colors.green.withOpacity(.6)),
                HorizontalLine(y: 140, dashArray: [8,4], color: Colors.orange.withOpacity(.6)),
                HorizontalLine(y: 160, dashArray: [8,4], color: Colors.red.withOpacity(.6)),
              ]),
            )),
          ),
          const SizedBox(height: 16),
          const Text('Напоминания', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ListTile(
              title: const Text('Утром'),
              subtitle: Text(_morning.format(context)),
              trailing: Switch(value: _remMorningOn, onChanged: _toggleMorning),
              onTap: () => _pickTime(true),
            )),
            const SizedBox(width: 8),
            Expanded(child: ListTile(
              title: const Text('Вечером'),
              subtitle: Text(_evening.format(context)),
              trailing: Switch(value: _remEveningOn, onChanged: _toggleEvening),
              onTap: () => _pickTime(false),
            )),
          ]),
          const SizedBox(height: 16),
          const Text('История', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          for (final m in _all)
            ListTile(
              leading: CircleAvatar(backgroundColor: _zoneColor(m), child: Text(m.pulse.toString(), style: const TextStyle(color: Colors.white))),
              title: Text('${m.sys}/${m.dia} мм рт. ст.'),
              subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(m.ts)),
            ),
        ],
      ),
    );
  }
}
