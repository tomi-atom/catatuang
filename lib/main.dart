import 'dart:io';

import 'package:art_sweetalert/art_sweetalert.dart';
import 'package:catatuang/temp_expense.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart'; // Tambahkan ini
import 'package:intl/date_symbol_data_local.dart';

import 'expense.dart';
import 'expense_database.dart'; // Tambahkan ini


// ===== Database Helper =====

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
    final amountController = TextEditingController(text: expense.amount.toStringAsFixed(0));
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
          SizedBox(height: 20),
        ],
      ),
    );

    if (result.isTapConfirmButton) {
      final updatedExpense = Expense(
        id: expense.id,
        description: descriptionController.text,
        amount: double.tryParse(amountController.text) ?? 0,
        date: DateTime.tryParse(dateController.text) ?? DateTime.now(),
      );

      await ExpenseDatabase.instance.updateExpense(updatedExpense);

      // Perbaikan: Gunakan setState untuk memperbarui UI
      await _loadExpenses(); // Panggil di luar setState


      // Tampilkan notifikasi sukses
      if (mounted) {
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

    if (result.isTapConfirmButton) {
      await ExpenseDatabase.instance.deleteExpense(id);

      await _loadExpenses();

      // Tampilkan notifikasi sukses
      if (mounted) {
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
  }

// Perbaikan metode _loadExpenses
  Future<void> _loadExpenses() async {
    print("🔄 Memuat ulang data...");
    final data = await ExpenseDatabase.instance.getExpenses();
    print("✅ Dapat ${data.length} data");
    if (mounted) {
      setState(() {
        _expenses = data;
      });
    }
  }

  Future<void> _pickAndCropImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      // Crop gambar
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Struk',
            toolbarColor: Colors.teal,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false, // ❗️Boleh atur bebas
          ),
          IOSUiSettings(
            title: 'Potong Struk',
            aspectRatioLockEnabled: false, // iOS juga bebas atur
          ),
        ],
      );

      if (croppedFile != null) {
        File imageFile = File(croppedFile.path);

        // Membaca teks dari gambar menggunakan OCR (Google ML Kit)
        final textRecognizer = GoogleMlKit.vision.textRecognizer();
        final inputImage = InputImage.fromFile(imageFile);
        final recognizedText = await textRecognizer.processImage(inputImage);

        // Ambil hasil teks OCR
        String extractedText = recognizedText.text;

        if (extractedText.isNotEmpty) {
          // Tampilkan teks yang dikenali
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Teks yang dikenali: $extractedText')),
          );

          // Lakukan proses berbicara menggunakan TTS
          processOCRText(extractedText);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada teks yang dikenali')),
          );
        }
      }
    }
  }
  Future<void> processOCRText(String ocrText) async {
    final lines = ocrText.split('\n');
    final regex = RegExp(r'^(.+?)\s{1,}(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|\d+)$');

    List<TempExpense> tempExpenses = [];

    for (var line in lines) {
      line = line.trim();
      final match = regex.firstMatch(line);

      if (match != null) {
        String rawName = match.group(1)!.trim();
        String rawAmount = match.group(2)!.trim();

        String normalized = rawAmount.replaceAll('.', '').replaceAll(',', '.');
        double? amount = double.tryParse(normalized);

        if (amount != null) {
          tempExpenses.add(TempExpense(description: rawName, amount: amount));
        }
      }
    }

    if (tempExpenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data belanja valid ditemukan')),
      );
      return;
    }

    // Tampilkan preview untuk konfirmasi
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Data Belanja'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tempExpenses.length,
                  itemBuilder: (context, index) {
                    final item = tempExpenses[index];
                    return ListTile(
                      title: TextFormField(
                        initialValue: item.description,
                        decoration: const InputDecoration(labelText: 'Nama Barang'),
                        onChanged: (val) => item.description = val,
                      ),
                      subtitle: TextFormField(
                        initialValue: item.amount.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Harga'),
                        onChanged: (val) {
                          double? parsed = double.tryParse(val.replaceAll('.', '').replaceAll(',', '.'));
                          if (parsed != null) item.amount = parsed;
                        },
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            tempExpenses.removeAt(index);
                          });
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            TextButton(
              child: const Text('Batal'),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('Simpan'),
              onPressed: () async {
                for (var item in tempExpenses) {
                  await ExpenseDatabase.instance.addExpense(
                    Expense(
                      description: item.description,
                      amount: item.amount,
                      date: DateTime.now(),
                    ),
                  );
                }
                await _loadExpenses();
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data berhasil disimpan')),
                );
              },
            ),
          ],
        );
      },
    );
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
      await _loadExpenses(); // Panggil di luar setState


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
                  trailing: Text('\Rp${e.amount.toStringAsFixed(0)}'),
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
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text("Foto Struk"),
            onPressed: _pickAndCropImage,
          ),


          const SizedBox(height: 50),
        ],
      ),
    );
  }
}