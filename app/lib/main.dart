import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BPLoggerApp());

/// ========= Модель =========
class BPRecord {
  final DateTime ts;
  final int sys, dia, pulse;
  final String? note;

  BPRecord({required this.ts, required this.sys, required this.dia, required this.pulse, this.note});

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
        pulse: (m['pulse'] as num).toInt(),
        note: m['note'] as String?,
      );

  static String csvHeader() => 'timestamp,sys,dia,pulse,note';
  String toCsv() =>
      '${ts.toIso8601String()},$sys,$dia,$pulse,"${(note ?? '').replaceAll('"', '""')}"';
}

/// ========= Хранилище =========
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

/// ========= Приложение =========
class BPLoggerApp extends StatelessWidget {
  const BPLoggerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BP Logger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
      ),
      home: const BPHomePage(),
    );
  }
}

/// ========= Главный экран =========
class BPHomePage extends StatefulWidget {
  const BPHomePage({super.key});
  @override
  State<BPHomePage> createState() => _BPHomePageState();
}

class _BPHomePageState extends State<BPHomePage> {
  final _sysC = TextEditingController();
  final _diaC = TextEditingController();
  final _pulseC = TextEditingController();
  final _noteC = TextEditingController();
  DateTime _ts = DateTime.now();

  final _formKey = GlobalKey<FormState>();
  List<BPRecord> _items = [];
  int? _editingIndex; // null => создаём, иначе редактируем

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _items = await BPStorage.load();
    setState(() {});
  }

  Future<void> _persist() async {
    await BPStorage.save(_items);
  }

  void _startEdit(int index) {
    final it = _items[index];
    _sysC.text = it.sys.toString();
    _diaC.text = it.dia.toString();
    _pulseC.text = it.pulse.toString();
    _noteC.text = it.note ?? '';
    _ts = it.ts;
    setState(() => _editingIndex = index);
  }

  void _clearForm() {
    _sysC.clear();
    _diaC.clear();
    _pulseC.clear();
    _noteC.clear();
    _ts = DateTime.now();
    _editingIndex = null;
    setState(() {});
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _ts,
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_ts));
    if (t == null) return;
    setState(() => _ts = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  String? _intValidator(String? v, {int min = 0, int max = 300}) {
    if (v == null || v.trim().isEmpty) return 'Нужно число';
    final n = int.tryParse(v);
    if (n == null) return 'Не похоже на число';
    if (n < min || n > max) return 'Диапазон $min..$max';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final rec = BPRecord(
      ts: _ts,
      sys: int.parse(_sysC.text),
      dia: int.parse(_diaC.text),
      pulse: int.parse(_pulseC.text),
      note: _noteC.text.trim().isEmpty ? null : _noteC.text.trim(),
    );

    if (_editingIndex == null) {
      _items.insert(0, rec);
    } else {
      _items[_editingIndex!] = rec;
    }
    await _persist();
    _clearForm();
  }

  Future<void> _delete(int index) async {
    _items.removeAt(index);
    await _persist();
    setState(() {});
  }

  void _exportCsv() {
    final csv = [
      BPRecord.csvHeader(),
      ..._items.map((e) => e.toCsv()),
    ].join('\n');

    // Показываем диалог с CSV и кнопкой "Копировать"
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CSV экспорт'),
        content: SingleChildScrollView(child: Text(csv)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    // В проде можно добавить share_plus для шаринга файла.
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom; // высота клавы
    return Scaffold(
      appBar: AppBar(
        title: const Text('BP Logger'),
        actions: [
          IconButton(
            tooltip: 'Экспорт CSV',
            onPressed: _items.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      // чтобы контент поднимался при клавиатуре
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // ----- Форма ввода -----
            Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _sysC,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'SYS'),
                            validator: (v) => _intValidator(v, min: 50, max: 280),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _diaC,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'DIA'),
                            validator: (v) => _intValidator(v, min: 30, max: 180),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _pulseC,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Pulse'),
                            validator: (v) => _intValidator(v, min: 20, max: 220),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _noteC,
                            decoration: const InputDecoration(labelText: 'Заметка (необязательно)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _pickDateTime,
                          icon: const Icon(Icons.event),
                          label: Text('${_ts.year}-${_two(_ts.month)}-${_two(_ts.day)} '
                              '${_two(_ts.hour)}:${_two(_ts.minute)}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            // ----- Список записей -----
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('Пока пусто. Добавь первую запись выше ☝️'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        return ListTile(
                          title: Text('${it.sys}/${it.dia} • ${it.pulse} bpm'),
                          subtitle: Text(
                            '${it.ts.toLocal()}${it.note == null ? '' : '\n${it.note}'}',
                          ),
                          onTap: () => _startEdit(i),
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
      // Кнопка «Сохранить» ПРИКОЛОЧЕНА к низу, SafeArea+пэддинг учитывают клавиатуру
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + (bottom > 0 ? bottom - 8 : 0)),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_editingIndex == null ? 'Сохранить' : 'Сохранить изменения'),
            ),
          ),
        ),
      ),
      // Быстрый сброс формы
      floatingActionButton: (_sysC.text.isNotEmpty ||
              _diaC.text.isNotEmpty ||
              _pulseC.text.isNotEmpty ||
              _noteC.text.isNotEmpty ||
              _editingIndex != null)
          ? FloatingActionButton(
              tooltip: 'Очистить форму',
              onPressed: _clearForm,
              child: const Icon(Icons.clear),
            )
          : null,
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
