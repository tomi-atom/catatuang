import 'package:art_sweetalert/art_sweetalert.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart'; // Tambahkan ini
import 'package:intl/date_symbol_data_local.dart'; // Tambahkan ini

class Expense {
  final int? id;
  final String description;
  final double amount;
  final DateTime date;

  Expense({
    this.id,
    required this.description,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      description: map['description'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
    );
  }
}

// ===== Database Helper =====
class ExpenseDatabase {
  static final ExpenseDatabase instance = ExpenseDatabase._init();
  static Database? _database;

  ExpenseDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expenses.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        description TEXT,
        amount REAL,
        date TEXT
      )
    ''');
  }

  Future<void> addExpense(Expense expense) async {
    final db = await instance.database;
    await db.insert('expenses', expense.toMap());
  }

  Future<List<Expense>> getExpenses() async {
    final db = await instance.database;
    final result = await db.query('expenses', orderBy: 'date DESC');
    return result.map((e) => Expense.fromMap(e)).toList();
  }

  // Tambahkan method update
  Future<void> updateExpense(Expense expense) async {
    final db = await instance.database;
    await db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  // Tambahkan method delete
  Future<void> deleteExpense(int id) async {
    final db = await instance.database;
    await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// ===== UI & Logic =====
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null); // Inisialisasi locale Indonesia
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Expense Tracker',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';
  List<Expense> _expenses = [];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    final data = await ExpenseDatabase.instance.getExpenses();
    setState(() {
      _expenses = data;
    });
  }


  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() => _lastWords = result.recognizedWords);
        },
        listenFor: const Duration(seconds: 5),
      );
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
    _processSpeech(_lastWords);
  }
  void _showEditDialog(Expense expense) async {
    final descriptionController = TextEditingController(text: expense.description);
    final amountController = TextEditingController(text: expense.amount.toString());
    final dateController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(expense.date),
    );

    final result = await ArtSweetAlert.show(
      context: context,
      artDialogArgs: ArtDialogArgs(
        type: ArtSweetAlertType.question,
        title: "Edit Pengeluaran",
        confirmButtonText: "Simpan",
        cancelButtonText: "Batal",
        showCancelBtn: true,
        customColumns: [
          TextField(
            controller: descriptionController,
            decoration: const InputDecoration(labelText: 'Deskripsi'),
          ),
          TextField(
            controller: amountController,
            decoration: const InputDecoration(labelText: 'Jumlah'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: dateController,
            decoration: const InputDecoration(labelText: 'Tanggal (YYYY-MM-DD)'),
          ),
        ],
      ),
    );

    if (result == true) {
      final updatedExpense = Expense(
        id: expense.id,
        description: descriptionController.text,
        amount: double.tryParse(amountController.text) ?? 0,
        date: DateTime.tryParse(dateController.text) ?? DateTime.now(),
      );

      await ExpenseDatabase.instance.updateExpense(updatedExpense);
      await _loadExpenses(); // <- Pastikan ini ada

      ArtSweetAlert.show(
        context: context,
        artDialogArgs: ArtDialogArgs(
          type: ArtSweetAlertType.success,
          title: "Berhasil!",
          text: "Pengeluaran telah diperbarui",
        ),
      );
    }
  }

  void _showDeleteDialog(int id) async {
    final result = await ArtSweetAlert.show(
      context: context,
      artDialogArgs: ArtDialogArgs(
        type: ArtSweetAlertType.warning,
        title: "Hapus Pengeluaran?",
        text: "Data yang dihapus tidak dapat dikembalikan",
        confirmButtonText: "Ya, Hapus",
        cancelButtonText: "Batal",
        showCancelBtn: true,
      ),
    );

    if (result == true) {
      await ExpenseDatabase.instance.deleteExpense(id);
      await _loadExpenses(); // <- Penting

      ArtSweetAlert.show(
        context: context,
        artDialogArgs: ArtDialogArgs(
          type: ArtSweetAlertType.success,
          title: "Terhapus!",
          text: "Pengeluaran telah dihapus",
        ),
      );
    }
  }

  void _processSpeech(String text) async {
    try {
      // Normalize text: remove extra spaces and convert to lowercase
      text = text.trim().toLowerCase();

      // Peta kata bilangan ke angka
      Map<String, String> angkaMap = {
        'nol': '0',
        'satu': '1',
        'dua': '2',
        'tiga': '3',
        'empat': '4',
        'lima': '5',
        'enam': '6',
        'tujuh': '7',
        'delapan': '8',
        'sembilan': '9',
        'sepuluh': '10',
        'sebelas': '11',
        'seratus': '100',
        'se ratus': '100',
        'seribu': '1000',
        'se ribu': '1000',
        'sejuta': '1000000',
        'se juta': '1000000',
      };

      // Ganti kata angka ke digit
      angkaMap.forEach((key, value) {
        text = text.replaceAll(RegExp('\\b$key\\b'), value);
      });

      // Gabungkan angka dan satuan
      text = text.replaceAllMapped(RegExp(r'(\d+)\s*(ribu|rbu)'), (m) => '${m[1]}000');
      text = text.replaceAllMapped(RegExp(r'(\d+)\s*(juta|jt)'), (m) => '${m[1]}000000');
      text = text.replaceAllMapped(RegExp(r'(\d+)\s*(ratus|rt)'), (m) => '${m[1]}00');

      // Ambil angka terakhir (biasanya jumlah uang)
      final RegExp amountRegex = RegExp(
          r'(\d{1,3}(?:\.?\d{3})*(?:,\d{1,2})?|\d+(?:,\d{1,2})?)'
      );
      final amountMatches = amountRegex.allMatches(text);

      if (amountMatches.isEmpty) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          const SnackBar(content: Text('Tidak menemukan jumlah uang dalam pesan')),
        );
        return;
      }

      // Take the last number as the amount (most likely the price)
      String amountString = amountMatches.last.group(0)!
          .replaceAll('.', '') // Remove thousand separators
          .replaceAll(',', '.'); // Convert decimal comma to dot

      final amount = double.tryParse(amountString);

      if (amount == null) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          const SnackBar(content: Text('Format jumlah uang tidak valid')),
        );
        return;
      }

      // Get description by removing the amount and number words from original text
      String description = text
          .replaceAll(amountMatches.last.group(0)!, '')
          .replaceAll(RegExp(r'(seratus|se ratus|ratus|seribu|se ribu|ribu|sejuta|se juta|juta)'), '')
          .trim();

      // If description is empty, use default
      if (description.isEmpty) {
        description = 'Pengeluaran';
      } else {
        // Capitalize first letter and clean up
        description = description
            .replaceAll(RegExp(r'\s+'), ' ') // Remove multiple spaces
            .trim();
        description = description.substring(0, 1).toUpperCase() +
            description.substring(1);
      }

      final expense = Expense(
        description: description,
        amount: amount,
        date: DateTime.now(),
      );

      await ExpenseDatabase.instance.addExpense(expense);
      _loadExpenses(); // Refresh list

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Disimpan: $description - Rp${amount.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                (Match m) => '${m[1]}.'
        )}')),
      );

      // Clear last words after successful save
      setState(() => _lastWords = '');

    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catat Uang Pake Suara'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadExpenses,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _expenses.isEmpty
                ? const Center(child: Text('Belum ada pengeluaran'))
                : ListView.builder(
              itemCount: _expenses.length,
              itemBuilder: (context, index) {
                final e = _expenses[index];
                return ListTile(
                  title: Text(e.description),
                  subtitle: Text(DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(e.date)),
                  trailing: Text('\Rp${e.amount.toStringAsFixed(2)}'),
                  onTap: () => _showEditDialog(e),
                  onLongPress: () => _showDeleteDialog(e.id!),
                );
              },
            )
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Dengar: $_lastWords'),
          ),
          ElevatedButton.icon(
            icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
            label: Text(_isListening ? 'Stop' : 'Ngomong'),
            onPressed: _isListening ? _stopListening : _startListening,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}