import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const BPLoggerApp());

class BPLoggerApp extends StatelessWidget {
  const BPLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF7B5BE6);
    return MaterialApp(
      title: 'BP Logger+',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      home: const BPHomePage(),
    );
  }
}

/// ----- Модель -----
class BPRecord {
  final DateTime ts; // дата измерения (локальная)
  final int sys;
  final int dia;
  final int? pulse;
  final String? note;

  const BPRecord({
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
        ts: DateTime.parse(m['ts'] as String).toLocal(),
        sys: (m['sys'] as num).toInt(),
        dia: (m['dia'] as num).toInt(),
        pulse: (m['pulse'] as num?)?.toInt(),
        note: m['note'] as String?,
      );
}

/// ----- Хранилище -----
class BPStorage {
  static const _key = 'bp_records_v2';

  static Future<List<BPRecord>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(BPRecord.fromMap).toList();
  }

  static Future<void> save(List<BPRecord> items) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((e) => e.toMap()).toList());
    await sp.setString(_key, raw);
  }
}

/// ----- Главная -----
class BPHomePage extends StatefulWidget {
  const BPHomePage({super.key});

  @override
  State<BPHomePage> createState() => _BPHomePageState();
}

class _BPHomePageState extends State<BPHomePage> with TickerProviderStateMixin {
  final _sysCtrl = TextEditingController();
  final _diaCtrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _pickTs = DateTime.now();

  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<BPRecord> _items = [];
  DateTime? _filterFrom;
  DateTime? _filterTo;

  List<BPRecord> get _filtered {
    var list = _items;
    if (_filterFrom != null || _filterTo != null) {
      list = list.where((r) {
        final d = DateTime(r.ts.year, r.ts.month, r.ts.day);
        final from = _filterFrom != null
            ? DateTime(_filterFrom!.year, _filterFrom!.month, _filterFrom!.day)
            : null;
        final to = _filterTo != null
            ? DateTime(_filterTo!.year, _filterTo!.month, _filterTo!.day)
            : null;
        final okFrom = from == null || !d.isBefore(from);
        final okTo = to == null || !d.isAfter(to);
        return okFrom && okTo;
      }).toList();
    }
    // сортировка по дате измерения (новые сверху)
    list.sort((a, b) => b.ts.compareTo(a.ts));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await BPStorage.load();
    data.sort((a, b) => b.ts.compareTo(a.ts));
    setState(() => _items = data);
  }

  Future<void> _saveRecord() async {
    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());
    final pulse = _pulseCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_pulseCtrl.text.trim());
    if (sys == null || dia == null) {
      _snack('Укажи SYS и DIA, котёнок 🐾');
      return;
    }
    if (sys < 60 || sys > 260 || dia < 30 || dia > 180) {
      _snack('Похоже на опечатку: проверь значения');
      return;
    }

    final rec = BPRecord(
      ts: _pickTs,
      sys: sys,
      dia: dia,
      pulse: pulse,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    setState(() {
      _items.add(rec);
      _items.sort((a, b) => b.ts.compareTo(a.ts));
    });
    await BPStorage.save(_items);
    _sysCtrl.clear();
    _diaCtrl.clear();
    _pulseCtrl.clear();
    _noteCtrl.clear();
    _pickTs = DateTime.now();
    _snack('Сохранил ✨');
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _pickTs,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickTs),
    );
    if (t == null) return;
    setState(() {
      _pickTs = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _pickFilter() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDateRange: _filterFrom != null && _filterTo != null
          ? DateTimeRange(start: _filterFrom!, end: _filterTo!)
          : null,
    );
    if (range == null) return;
    setState(() {
      _filterFrom = range.start;
      _filterTo = range.end;
    });
  }

  void _clearFilter() => setState(() {
        _filterFrom = null;
        _filterTo = null;
      });

  Future<void> _deleteRecord(int index) async {
    final rec = _filtered[index];
    setState(() => _items.removeWhere((r) => identical(r, rec)));
    await BPStorage.save(_items);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final title = 'BP Logger+';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Фильтр по датам',
            onPressed: _pickFilter,
            icon: const Icon(Icons.filter_alt),
          ),
          if (_filterFrom != null || _filterTo != null)
            IconButton(
              tooltip: 'Сбросить фильтр',
              onPressed: _clearFilter,
              icon: const Icon(Icons.filter_alt_off),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Список'),
            Tab(text: 'Графики'),
          ],
        ),
      ),

      // Поля ввода + список / графики
      body: TabBarView(
        controller: _tabs,
        children: [
          // ----- Список -----
          Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _InputCard(
                  sysCtrl: _sysCtrl,
                  diaCtrl: _diaCtrl,
                  pulseCtrl: _pulseCtrl,
                  noteCtrl: _noteCtrl,
                  ts: _pickTs,
                  onPickTs: _pickDateTime,
                ),
              ),
              const SizedBox(height: 8),
              _StatsBar(records: _filtered),
              const Divider(height: 1),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(child: Text('Пока пусто. Добавь первую запись.'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _filtered[i];
                          return ListTile(
                            title: Text('${r.sys}/${r.dia}'
                                '${r.pulse == null ? '' : '  •  ${r.pulse} bpm'}'),
                            subtitle: Text('${df.format(r.ts)}'
                                '${r.note == null ? '' : '\n${r.note}'}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteRecord(i),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 88), // запас под кнопку
            ],
          ),

          // ----- Графики -----
          _ChartsTab(records: _filtered),
        ],
      ),

      // Фиксированная кнопка "Сохранить"
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          color: Theme.of(context).colorScheme.surface,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Сохранить'),
              onPressed: _saveRecord,
            ),
          ),
        ),
      ),
    );
  }
}

/// ----- Виджеты ввода -----
class _InputCard extends StatelessWidget {
  final TextEditingController sysCtrl;
  final TextEditingController diaCtrl;
  final TextEditingController pulseCtrl;
  final TextEditingController noteCtrl;
  final DateTime ts;
  final VoidCallback onPickTs;

  const _InputCard({
    required this.sysCtrl,
    required this.diaCtrl,
    required this.pulseCtrl,
    required this.noteCtrl,
    required this.ts,
    required this.onPickTs,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Card(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            final isNarrow = c.maxWidth < 480;
            final spacing = const SizedBox(width: 12, height: 12);
            final rowChildren = <Widget>[
              Expanded(
                child: TextField(
                  controller: sysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'SYS',
                    hintText: '120',
                  ),
                ),
              ),
              spacing,
              Expanded(
                child: TextField(
                  controller: diaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'DIA',
                    hintText: '80',
                  ),
                ),
              ),
              spacing,
              Expanded(
                child: TextField(
                  controller: pulseCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Pulse',
                    hintText: '70',
                  ),
                ),
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                isNarrow
                    ? Column(
                        children: [
                          Row(children: [rowChildren[0], rowChildren[1]]),
                          spacing,
                          Row(children: [rowChildren[2]]),
                        ],
                      )
                    : Row(children: rowChildren),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Примечание (необязательно)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: onPickTs,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(df.format(ts)),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ----- Верхняя панель со средними -----
class _StatsBar extends StatelessWidget {
  final List<BPRecord> records;
  const _StatsBar({required this.records});

  Map<String, num?> _calcAvg(Duration span) {
    final now = DateTime.now();
    final from = now.subtract(span);
    final sel = records.where((r) => r.ts.isAfter(from)).toList();
    if (sel.isEmpty) return {'sys': null, 'dia': null, 'pulse': null};
    num avgSys = 0, avgDia = 0, avgPulse = 0;
    var cntPulse = 0;
    for (final r in sel) {
      avgSys += r.sys;
      avgDia += r.dia;
      if (r.pulse != null) {
        avgPulse += r.pulse!;
        cntPulse++;
      }
    }
    return {
      'sys': (avgSys / sel.length),
      'dia': (avgDia / sel.length),
      'pulse': cntPulse == 0 ? null : (avgPulse / cntPulse),
    };
  }

  @override
  Widget build(BuildContext context) {
    final day = _calcAvg(const Duration(days: 1));
    final week = _calcAvg(const Duration(days: 7));
    final month = _calcAvg(const Duration(days: 30));

    Widget cell(String title, Map<String, num?> v) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 4),
            Text(
              [
                v['sys'] == null || v['dia'] == null
                    ? '—'
                    : '${v['sys']!.round()}/${v['dia']!.round()}',
                if (v['pulse'] != null) '· ${v['pulse']!.round()} bpm',
              ].join('  '),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: cell('24 часа', day)),
          Expanded(child: cell('7 дней', week)),
          Expanded(child: cell('30 дней', month)),
        ],
      ),
    );
  }
}

/// ----- Вкладка с графиками -----
class _ChartsTab extends StatelessWidget {
  final List<BPRecord> records;
  const _ChartsTab({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(child: Text('Нет данных для графиков'));
    }
    final sorted = [...records]..sort((a, b) => a.ts.compareTo(b.ts));

    // Преобразуем в точки
    final base = sorted.first.ts.millisecondsSinceEpoch.toDouble();
    List<FlSpot> sSys = [], sDia = [], sPulse = [];
    for (final r in sorted) {
      final x = (r.ts.millisecondsSinceEpoch.toDouble() - base) / 86400000.0; // дни
      sSys.add(FlSpot(x, r.sys.toDouble()));
      sDia.add(FlSpot(x, r.dia.toDouble()));
      if (r.pulse != null) sPulse.add(FlSpot(x, r.pulse!.toDouble()));
    }

    Widget chart(String title, List<FlSpot> spots,
        {double minY = 40, double maxY = 260}) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    lineTouchData: const LineTouchData(enabled: true),
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: (spots.length / 6).clamp(1, 7).toDouble(),
                          getTitlesWidget: (v, meta) {
                            final millis = base + v * 86400000.0;
                            final d =
                                DateTime.fromMillisecondsSinceEpoch(millis.toInt());
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(DateFormat('MM-dd').format(d),
                                  style: Theme.of(context).textTheme.labelSmall),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: true),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                        barWidth: 3,
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        chart('Систолическое (SYS)', sSys, minY: 70, maxY: 260),
        chart('Диастолическое (DIA)', sDia, minY: 40, maxY: 180),
        if (sPulse.isNotEmpty) chart('Пульс', sPulse, minY: 40, maxY: 180),
        const SizedBox(height: 16),
      ],
    );
  }
}
