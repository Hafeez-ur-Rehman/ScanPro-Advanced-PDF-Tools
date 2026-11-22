import 'dart:io';
import 'dart:typed_data';

import 'package:doc_scan_flutter/doc_scan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'dart:ui' as ui;

bool cloudAvailable = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      cloudAvailable = true;
    } catch (error) {
      // The app remains fully usable offline when Firebase is not configured.
      debugPrint('Firebase initialization skipped: $error');
    }
  }
  runApp(const ScannerApp());
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ScanPro',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<File> pages = [];
  final picker = ImagePicker();
  bool busy = false;
  String? lastOcrText;
  User? get currentUser => cloudAvailable ? FirebaseAuth.instance.currentUser : null;

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  Future<Directory> _scanDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/ScanPro/Scans');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<File> _keepInAppStorage(File source) async {
    final folder = await _scanDirectory();
    final extension = source.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final target = File(
      '${folder.path}/Scan_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    return source.copy(target.path);
  }

  /// Uses ML Kit on Android and VisionKit on iOS. The browser build uses
  /// the separate web/PWA scanner because this native plugin is mobile-only.
  Future<void> smartScan() async {
    if (kIsWeb) {
      await addPage(ImageSource.camera);
      return;
    }
    if (busy) return;
    setState(() => busy = true);
    try {
      final List<String>? result = await DocumentScanner.scan(
        format: DocumentScannerFormat.jpeg,
      );
      if (result == null || result.isEmpty) return;
      var added = 0;
      for (final path in result) {
        final scannedFile = File(path);
        if (!await scannedFile.exists()) continue;
        final saved = await _keepInAppStorage(scannedFile);
        pages.add(saved);
        added++;
      }
      if (mounted) setState(() {});
      message(added == 0
          ? 'The scanner did not return any image pages.'
          : '$added scanned page${added == 1 ? '' : 's'} added.');
    } catch (e) {
      message('Smart Scan could not start: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addPage(ImageSource source) async {
    if (busy) return;
    try {
      setState(() => busy = true);
      final XFile? shot = await picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2800,
      );
      if (shot == null) return;
      final cropped = await ImageCropper().cropImage(
        sourcePath: shot.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust document',
            toolbarColor: const Color(0xFF1769AA),
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Adjust document'),
        ],
      );
      if (cropped == null || !mounted) return;
      final saved = await _keepInAppStorage(File(cropped.path));
      setState(() => pages.add(saved));
    } catch (e) {
      message('Could not add image: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> recognizePage(File file) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Use the ScanPro Web app for browser-based English OCR.',
      );
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(file.path);
      final result = await recognizer.processImage(input);
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }

  Future<void> extractText() async {
    if (pages.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      final output = StringBuffer();
      for (var i = 0; i < pages.length; i++) {
        if (mounted) message('Recognizing page ${i + 1} of ${pages.length}…');
        final text = await recognizePage(pages[i]);
        output.writeln('--- Page ${i + 1} ---');
        output.writeln(text.isEmpty ? '[No readable text found]' : text);
        output.writeln();
      }
      lastOcrText = output.toString().trim();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recognized English text'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(lastOcrText ?? '')),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final dir = await _scanDirectory();
                final file = File('${dir.path}/Recognized_Text.txt');
                await file.writeAsString(lastOcrText ?? '');
                if (context.mounted) Navigator.pop(context);
                await Share.shareXFiles([XFile(file.path)]);
              },
              child: const Text('Save / Share TXT'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      message('English OCR failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<File> makePdf() async {
    final doc = pw.Document();
    for (final file in pages) {
      final bytes = await file.readAsBytes();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (_) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    final folder = await _scanDirectory();
    final output = File(
      '${folder.path}/ScanPro_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await output.writeAsBytes(await doc.save(), flush: true);
    return output;
  }

  Future<void> exportPdf() async {
    if (pages.isEmpty || busy) {
      message('Please scan at least one page first.');
      return;
    }
    try {
      setState(() => busy = true);
      final file = await makePdf();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Scanned with ScanPro',
      );
    } catch (e) {
      message('PDF export failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void removePage(int index) {
    pages.removeAt(index);
    setState(() {});
    // Keep the saved file on device; it may be useful if a PDF was already made.
    message('Page removed from the current scan.');
  }

  Future<List<File>> _pickPdfFiles({bool multiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: multiple,
      withData: false,
    );
    return (result?.paths ?? []).whereType<String>().map((path) => File(path)).where((f) => f.existsSync()).toList();
  }

  Future<File> _outputPdf(String prefix) async {
    final folder = await _scanDirectory();
    return File('${folder.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  Future<void> mergePdfs() async {
    try {
      final inputs = await _pickPdfFiles();
      if (inputs.length < 2) { message('Select at least two PDF files to merge.'); return; }
      setState(() => busy = true);
      final output = sf.PdfDocument();
      sf.PdfSection? section;
      for (final file in inputs) {
        final source = sf.PdfDocument(inputBytes: await file.readAsBytes());
        for (var i = 0; i < source.pages.count; i++) {
          final template = source.pages[i].createTemplate();
          if (section == null || section.pageSettings.size != template.size) {
            section = output.sections!.add();
            section.pageSettings.size = template.size;
            section.pageSettings.margins.all = 0;
          }
          section.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
        }
        source.dispose();
      }
      final target = await _outputPdf('Merged');
      await target.writeAsBytes(await output.save(), flush: true);
      output.dispose();
      await Share.shareXFiles([XFile(target.path)], text: 'Merged with ScanPro');
      message('PDF files merged successfully.');
    } catch (e) { message('Merge failed. Check that the PDFs are not password-protected: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> splitPdf() async {
    try {
      final inputs = await _pickPdfFiles(multiple: false);
      if (inputs.isEmpty) return;
      final source = sf.PdfDocument(inputBytes: await inputs.first.readAsBytes());
      if (source.pages.count < 2) { source.dispose(); message('This PDF has only one page.'); return; }
      setState(() => busy = true);
      final outputs = <XFile>[];
      for (var i = 0; i < source.pages.count; i++) {
        final doc = sf.PdfDocument();
        final template = source.pages[i].createTemplate();
        final section = doc.sections!.add();
        section.pageSettings.size = template.size;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
        final target = await _outputPdf('Split_Page_${i + 1}');
        await target.writeAsBytes(await doc.save(), flush: true);
        outputs.add(XFile(target.path));
        doc.dispose();
      }
      source.dispose();
      await Share.shareXFiles(outputs, text: 'Split pages from ScanPro');
      message('Created ${outputs.length} single-page PDFs.');
    } catch (e) { message('Split failed: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> compressPdf() async {
    try {
      final inputs = await _pickPdfFiles(multiple: false);
      if (inputs.isEmpty) return;
      setState(() => busy = true);
      final doc = sf.PdfDocument(inputBytes: await inputs.first.readAsBytes());
      doc.fileStructure.incrementalUpdate = false;
      doc.compressionLevel = sf.PdfCompressionLevel.best;
      final target = await _outputPdf('Compressed');
      await target.writeAsBytes(await doc.save(), flush: true);
      doc.dispose();
      final before = inputs.first.lengthSync();
      final after = target.lengthSync();
      await Share.shareXFiles([XFile(target.path)], text: 'Compressed with ScanPro');
      message('PDF optimized: ${(before / 1024).toStringAsFixed(0)} KB → ${(after / 1024).toStringAsFixed(0)} KB. Image-heavy files may need image downsampling for larger savings.');
    } catch (e) { message('Compression failed: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> protectPdf() async {
    final inputs = await _pickPdfFiles(multiple: false);
    if (inputs.isEmpty) return;
    final passwordController = TextEditingController();
    final password = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Protect PDF'),
      content: TextField(controller: passwordController, obscureText: true, autofocus: true,
        decoration: const InputDecoration(labelText: 'Open password', helperText: 'Use at least 6 characters')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, passwordController.text), child: const Text('Protect'))],
    ));
    passwordController.dispose();
    if (password == null) return;
    if (password.length < 6) { message('Please use a password with at least 6 characters.'); return; }
    try {
      setState(() => busy = true);
      final doc = sf.PdfDocument(inputBytes: await inputs.first.readAsBytes());
      doc.security.userPassword = password;
      doc.security.ownerPassword = '${password}ScanProOwner';
      doc.security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;
      final target = await _outputPdf('Protected');
      await target.writeAsBytes(await doc.save(), flush: true);
      doc.dispose();
      await Share.shareXFiles([XFile(target.path)], text: 'Password-protected PDF');
      message('Password protection applied. Keep your password safe.');
    } catch (e) { message('Could not protect this PDF: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> addSignature() async {
    final inputs = await _pickPdfFiles(multiple: false);
    if (inputs.isEmpty) return;
    final signature = await showDialog<Uint8List>(context: context, builder: (_) => const _SignatureDialog());
    if (signature == null || signature.isEmpty) return;
    try {
      setState(() => busy = true);
      final doc = sf.PdfDocument(inputBytes: await inputs.first.readAsBytes());
      final page = doc.pages[0];
      final image = sf.PdfBitmap(signature);
      final size = page.getClientSize();
      page.graphics.drawImage(image, Rect.fromLTWH(24, size.height - 100, 190, 64));
      final target = await _outputPdf('Signed');
      await target.writeAsBytes(await doc.save(), flush: true);
      doc.dispose();
      await Share.shareXFiles([XFile(target.path)], text: 'Signed PDF');
      message('Signature added to the first page. This is a visible handwritten mark, not a certificate-backed digital signature.');
    } catch (e) { message('Could not add signature: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> manageFolders() async {
    final root = await _scanDirectory();
    final folders = Directory('${root.parent.path}/Folders');
    if (!await folders.exists()) await folders.create(recursive: true);
    final nameController = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Create document folder'),
      content: TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, nameController.text.trim()), child: const Text('Create'))],
    ));
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    await Directory('${folders.path}/$safeName').create(recursive: true);
    if (mounted) message('Folder "$safeName" created. Use the local library to organize PDFs into folders.');
    await showLocalLibrary();
  }

  Future<void> showAccount() async {
    if (!cloudAvailable) {
      message('Cloud backup is not configured yet. Add your Firebase settings to GitHub Actions Secrets.');
      return;
    }
    if (currentUser != null) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.cloud_done_outlined)),
            title: Text(currentUser!.email ?? 'Signed in'),
            subtitle: const Text('Your private cloud account'),
            trailing: TextButton(
              onPressed: () async {
                Navigator.pop(sheetContext);
                await FirebaseAuth.instance.signOut();
                if (mounted) message('Signed out. Your local scans are unchanged.');
              },
              child: const Text('Sign out'),
            ),
          ),
        ),
      );
      return;
    }
    final email = TextEditingController();
    final password = TextEditingController();
    var createAccount = false;
    var submitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(createAccount ? 'Create ScanPro account' : 'Sign in to ScanPro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
              const SizedBox(height: 8),
              TextButton(
                onPressed: submitting ? null : () => setDialogState(() => createAccount = !createAccount),
                child: Text(createAccount ? 'Already have an account? Sign in' : 'New here? Create an account'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting ? null : () async {
                if (email.text.trim().isEmpty || password.text.length < 6) {
                  message('Enter a valid email and a password of at least 6 characters.');
                  return;
                }
                setDialogState(() => submitting = true);
                try {
                  if (createAccount) {
                    await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
                  } else {
                    await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) { setState(() {}); message('Cloud account connected.'); }
                } on FirebaseAuthException catch (e) {
                  message(e.message ?? 'Account sign-in failed.');
                  setDialogState(() => submitting = false);
                } catch (e) {
                  message('Could not connect account: $e');
                  setDialogState(() => submitting = false);
                }
              },
              child: Text(submitting ? 'Please wait…' : (createAccount ? 'Create account' : 'Sign in')),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    password.dispose();
  }

  Future<void> backupCurrentScan() async {
    if (!cloudAvailable) {
      message('Cloud backup needs Firebase setup. See FIREBASE_SETUP.md.');
      return;
    }
    if (currentUser == null) {
      await showAccount();
      if (currentUser == null) return;
    }
    if (pages.isEmpty || busy) {
      message('Scan at least one page before backing up.');
      return;
    }
    setState(() => busy = true);
    try {
      final pdf = await makePdf();
      final uid = currentUser!.uid;
      final id = 'scan_${DateTime.now().millisecondsSinceEpoch}';
      final storagePath = 'users/$uid/documents/$id.pdf';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putFile(pdf, SettableMetadata(contentType: 'application/pdf'));
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('documents').doc(id).set({
        'kind': 'pdf',
        'name': pdf.uri.pathSegments.last,
        'storagePath': storagePath,
        'contentType': 'application/pdf',
        'pageCount': pages.length,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) message('PDF backed up securely to your private cloud library.');
    } catch (e) {
      if (mounted) message('Cloud backup failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showCloudLibrary() async {
    if (!cloudAvailable) {
      message('Cloud library is not configured. See FIREBASE_SETUP.md.');
      return;
    }
    if (currentUser == null) {
      await showAccount();
      if (currentUser == null) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * .72,
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('Cloud Documents', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).collection('documents').where('kind', isEqualTo: 'pdf').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('Could not load cloud documents: ${snapshot.error}'));
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Center(child: Text('No cloud documents yet.'));
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      return ListTile(
                        leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF1769AA)),
                        title: Text((data['name'] as String?) ?? 'Scanned document', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${data['pageCount'] ?? '?'} pages · ${_dateLabel(data['createdAt'] ?? data['updatedAt'])}'),
                        trailing: IconButton(
                          tooltip: 'Restore to this device',
                          icon: const Icon(Icons.download_for_offline_outlined),
                          onPressed: () async {
                            try {
                              final storagePath = data['storagePath'] as String;
                              final bytes = await FirebaseStorage.instance.ref(storagePath).getData(40 * 1024 * 1024);
                              if (bytes == null) throw StateError('Cloud file is empty.');
                              final folder = await _scanDirectory();
                              final local = File('${folder.path}/${doc.id}.pdf');
                              await local.writeAsBytes(bytes, flush: true);
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              if (mounted) message('Document restored to this device: ${local.path.split('/').last}');
                            } catch (e) { message('Restore failed: $e'); }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate().toLocal();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return 'Just uploaded';
  }

  Future<void> showLocalLibrary() async {
    final root = await _scanDirectory();
    final folderRoot = Directory('${root.parent.path}/Folders');
    if (!await folderRoot.exists()) await folderRoot.create(recursive: true);
    final files = <File>[];
    files.addAll(root.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.pdf')));
    files.addAll(folderRoot.listSync().whereType<Directory>().expand((d) => d.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.pdf'))));
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final folders = folderRoot.listSync().whereType<Directory>().toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => SizedBox(height: MediaQuery.of(sheetContext).size.height * .78,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Expanded(child: Text('On-device Library', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: () { Navigator.pop(sheetContext); manageFolders(); }, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('New folder')),
          ])),
          if (folders.isNotEmpty) SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: folders.map((d) => Padding(
            padding: const EdgeInsets.only(right: 8), child: Chip(avatar: const Icon(Icons.folder_outlined), label: Text(d.uri.pathSegments.where((e) => e.isNotEmpty).last)),
          )).toList())),
          Expanded(child: files.isEmpty ? const Center(child: Text('No saved PDFs yet. Export a scan to create one.')) : ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final inFolder = file.parent.path != root.path;
              return ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF1769AA)),
                title: Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${(file.lengthSync() / 1024).toStringAsFixed(0)} KB${inFolder ? ' • ${file.parent.uri.pathSegments.where((e) => e.isNotEmpty).last}' : ' • Unfiled'}'),
                trailing: PopupMenuButton<String>(onSelected: (action) async {
                  if (action == 'share') await Share.shareXFiles([XFile(file.path)]);
                  if (action == 'move') {
                    final selected = await showDialog<Directory>(context: context, builder: (ctx) => SimpleDialog(title: const Text('Move to folder'), children: folders.map((d) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d), child: Text(d.uri.pathSegments.where((e) => e.isNotEmpty).last))).toList()));
                    if (selected != null) { final dest = File('${selected.path}/${file.uri.pathSegments.last}'); await file.rename(dest.path); if (mounted) { Navigator.pop(sheetContext); showLocalLibrary(); } }
                  }
                }, itemBuilder: (_) => const [PopupMenuItem(value: 'share', child: Text('Share')), PopupMenuItem(value: 'move', child: Text('Move to folder'))]),
              );
            },
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ScanPro', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Local library', onPressed: showLocalLibrary, icon: const Icon(Icons.folder_open_outlined)),
          IconButton(tooltip: 'Cloud library', onPressed: showCloudLibrary, icon: const Icon(Icons.cloud_outlined)),
          IconButton(tooltip: 'Account', onPressed: showAccount, icon: Icon(currentUser == null ? Icons.account_circle_outlined : Icons.cloud_done_outlined)),
          IconButton(
            tooltip: 'Export PDF',
            onPressed: busy || pages.isEmpty ? null : exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF102A43), Color(0xFF1769AA), Color(0xFF20A4C7)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.document_scanner_outlined, color: Colors.white, size: 34),
                  SizedBox(height: 12),
                  Text('Scan. Enhance. Share.',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text('Detect document edges and create clean digital copies.',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.document_scanner_outlined,
                      title: 'Smart Scan',
                      subtitle: 'Auto detect & crop',
                      onTap: busy ? null : smartScan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.photo_library_outlined,
                      title: 'Gallery',
                      subtitle: 'Import & crop',
                      onTap: busy ? null : () => addPage(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _ToolChip(icon: Icons.merge_type, label: 'Merge', onTap: busy ? null : mergePdfs),
                _ToolChip(icon: Icons.call_split, label: 'Split', onTap: busy ? null : splitPdf),
                _ToolChip(icon: Icons.compress, label: 'Compress', onTap: busy ? null : compressPdf),
                _ToolChip(icon: Icons.lock_outline, label: 'Protect', onTap: busy ? null : protectPdf),
                _ToolChip(icon: Icons.draw_outlined, label: 'Sign', onTap: busy ? null : addSignature),
                _ToolChip(icon: Icons.create_new_folder_outlined, label: 'Folders', onTap: busy ? null : manageFolders),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text('Current scan',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${pages.length} pages', style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            Expanded(
              child: pages.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.note_add_outlined, size: 58, color: Color(0xFF9AA7B4)),
                          SizedBox(height: 12),
                          Text('No scans yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Tap Smart Scan to detect document edges automatically.',
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: .78,
                      ),
                      itemCount: pages.length,
                      itemBuilder: (context, index) => Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(pages[index], fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: IconButton.filled(
                              style: IconButton.styleFrom(backgroundColor: Colors.white),
                              onPressed: () => removePage(index),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Page ${index + 1}', style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            if (busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: busy || pages.isEmpty ? null : extractText,
                    icon: const Icon(Icons.text_snippet_outlined),
                    label: const Text('OCR'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    onPressed: busy || pages.isEmpty ? null : exportPdf,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('PDF'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: busy || pages.isEmpty ? null : backupCurrentScan,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Backup'),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback? onTap;
  const _ToolChip({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 18, color: const Color(0xFF1769AA)),
    label: Text(label), onPressed: onTap,
    backgroundColor: Colors.white, side: BorderSide(color: Colors.blueGrey.shade100),
  );
}

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog();
  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}
class _SignatureDialogState extends State<_SignatureDialog> {
  final List<Offset?> points = [];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Draw your signature'),
    content: SizedBox(width: 320, height: 190, child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blueGrey.shade200), borderRadius: BorderRadius.circular(12)),
      child: GestureDetector(onPanUpdate: (d) => setState(() => points.add(d.localPosition)), onPanEnd: (_) => points.add(null),
        child: CustomPaint(painter: _SignaturePainter(points), child: const SizedBox.expand())),
    )),
    actions: [TextButton(onPressed: () => setState(() => points.clear()), child: const Text('Clear')),
      FilledButton(onPressed: points.whereType<Offset>().length < 2 ? null : () async {
        const width = 900.0, height = 520.0;
        final recorder = ui.PictureRecorder(); final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0x00FFFFFF), BlendMode.src);
        final paint = Paint()..color = const Color(0xFF142B4A)..strokeWidth = 5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
        for (var i = 0; i < points.length - 1; i++) { final a = points[i], b = points[i + 1]; if (a != null && b != null) canvas.drawLine(Offset(a.dx * width / 320, a.dy * height / 190), Offset(b.dx * width / 320, b.dy * height / 190), paint); }
        final picture = recorder.endRecording(); final image = await picture.toImage(width.toInt(), height.toInt());
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (context.mounted && data != null) Navigator.pop(context, data.buffer.asUint8List());
      }, child: const Text('Use signature'))],
  );
}
class _SignaturePainter extends CustomPainter {
  final List<Offset?> points; _SignaturePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) { final paint = Paint()..color = const Color(0xFF142B4A)..strokeWidth = 2.5..strokeCap = StrokeCap.round; for (var i=0; i<points.length-1; i++) { final a=points[i], b=points[i+1]; if (a!=null && b!=null) canvas.drawLine(a,b,paint); } }
  @override bool shouldRepaint(covariant _SignaturePainter oldDelegate) => oldDelegate.points != points;
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, size: 30, color: const Color(0xFF1769AA)),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        ),
      );
}
