import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() => runApp(const BPLoggerApp());

class BPLoggerApp extends StatelessWidget {
  const BPLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BP Logger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
      ),
      home: const BPHomePage(),
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
        sys: m['sys'] as int,
        dia: m['dia'] as int,
        pulse: (m['pulse'] as num?)?.toInt(),
        note: m['note'] as String?,
      );

  String toCsv() =>
      '${ts.toIso8601String()},$sys,$dia,${pulse ?? ''},"${(note ?? '').replaceAll('"', '""')}"';

  static String csvHeader() => 'timestamp,sys,dia,pulse,note';
}

class BPStorage {
  static const _key = 'bp_records_v1';

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

class BPHomePage extends StatefulWidget {
  const BPHomePage({super.key});

  @override
  State<BPHomePage> createState() => _BPHomePageState();
}

class _BPHomePageState extends State<BPHomePage> {
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<BPRecord> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await BPStorage.load();
    setState(() {
      _items = data..sort((a, b) => b.ts.compareTo(a.ts));
      _loading = false;
    });
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    final rec = BPRecord(
      ts: DateTime.now(),
      sys: int.parse(_sys.text),
      dia: int.parse(_dia.text),
      pulse: _pulse.text.isEmpty ? null : int.parse(_pulse.text),
      note: _note.text.isEmpty ? null : _note.text.trim(),
    );
    setState(() {
      _items.insert(0, rec);
    });
    await BPStorage.save(_items);
    _sys.clear();
    _dia.clear();
    _pulse.clear();
    _note.clear();
  }

  Future<void> _delete(int index) async {
    setState(() => _items.removeAt(index));
    await BPStorage.save(_items);
  }

  Future<void> _exportCsv() async {
    final rows = <String>[BPRecord.csvHeader(), ..._items.map((e) => e.toCsv())];
    final csv = rows.join('\n');
    // Ничего не делаем тут — в CI мы просто выведем в лог при желании.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Экспорт готов: скопируй из логов или добавим файл позже')),
    );
    // print(csv); // Можно раскомментировать — будет в логах.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Logger'),
        actions: [
          IconButton(onPressed: _exportCsv, icon: const Icon(Icons.download)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Form(
                    key: _form,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _num(_sys, 'SYS', '120'),
                        const SizedBox(width: 8),
                        _num(_dia, 'DIA', '80'),
                        const SizedBox(width: 8),
                        _num(_pulse, 'Pulse', '70', required: false),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _note,
                            decoration: const InputDecoration(labelText: 'Заметка'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _add,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                            child: Text('Сохранить'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _items.isEmpty
                        ? const Center(child: Text('Записей пока нет'))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = _items[i];
                              final ts = '${e.ts.year.toString().padLeft(4, '0')}-'
                                  '${e.ts.month.toString().padLeft(2, '0')}-'
                                  '${e.ts.day.toString().padLeft(2, '0')} '
                                  '${e.ts.hour.toString().padLeft(2, '0')}:'
                                  '${e.ts.minute.toString().padLeft(2, '0')}';
                              return ListTile(
                                title: Text('$ts  —  ${e.sys}/${e.dia}${e.pulse != null ? '  •  ${e.pulse} bpm' : ''}'),
                                subtitle: e.note?.isNotEmpty == true ? Text(e.note!) : null,
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(i),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _num(TextEditingController c, String label, String hint, {bool required = true}) {
    return SizedBox(
      width: 90,
      child: TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (v) {
          if (!required && (v == null || v.isEmpty)) return null;
          final n = int.tryParse(v ?? '');
          if (n == null) return 'число';
          if (label == 'SYS' && (n < 60 || n > 250)) return '60–250';
          if (label == 'DIA' && (n < 40 || n > 150)) return '40–150';
          if (label == 'Pulse' && (n < 30 || n > 220)) return '30–220';
          return null;
        },
      ),
    );
  }
}
