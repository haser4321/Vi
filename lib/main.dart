
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore db = FirebaseFirestore.instance;
final FirebaseStorage storage = FirebaseStorage.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    runApp(const NeighborApp());
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'تعذر تشغيل Firebase.\n'
              'تأكد من إعداد المشروع وملف google-services.json.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
  }
}

class NeighborApp extends StatefulWidget {
  const NeighborApp({super.key});

  @override
  State<NeighborApp> createState() => _NeighborAppState();
}

class _NeighborAppState extends State<NeighborApp> {
  bool dark = true;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF397A72);

    return MaterialApp(
      title: 'جيران',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101614),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AuthGate(
          dark: dark,
          onThemeChanged: (value) => setState(() => dark = value),
        ),
      ),
    );
  }
}

void notify(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );
}

String authError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'هذا البريد مسجل بالفعل.';
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة؛ استخدم 6 أحرف على الأقل.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'بيانات تسجيل الدخول غير صحيحة.';
      case 'operation-not-allowed':
        return 'فعّل تسجيل البريد وكلمة المرور في Firebase.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت.';
      case 'too-many-requests':
        return 'محاولات كثيرة. حاول لاحقًا.';
      default:
        return 'تعذر إكمال العملية: ${error.code}';
    }
  }
  return 'حدث خطأ. تحقق من الاتصال وإعدادات Firebase.';
}

class AuthGate extends StatelessWidget {
  final bool dark;
  final ValueChanged<bool> onThemeChanged;

  const AuthGate({
    super.key,
    required this.dark,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) return const LoginPage();

        return PinGate(
          key: ValueKey(user.uid),
          uid: user.uid,
          child: MainPage(
            dark: dark,
            onThemeChanged: onThemeChanged,
          ),
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool registering = false;
  bool busy = false;
  bool hidePassword = true;

  Future<void> submit() async {
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;

    if (!email.contains('@') || password.length < 6) {
      notify(context, 'أدخل بريدًا صحيحًا وكلمة مرور من 6 أحرف على الأقل.');
      return;
    }

    setState(() => busy = true);

    try {
      if (registering) {
        final result = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = result.user;
        if (user != null) {
          await db.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'email': email,
            'createdAt': FieldValue.serverTimestamp(),
          });

          await user.sendEmailVerification();

          if (mounted) {
            notify(context, 'تم إنشاء الحساب. تحقق من بريدك الإلكتروني.');
          }
        }
      } else {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } catch (error) {
      if (mounted) notify(context, authError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (!email.contains('@')) {
      notify(context, 'أدخل بريدك الإلكتروني أولًا.');
      return;
    }

    try {
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        notify(context, 'إذا كان البريد مسجلًا، فستصلك رسالة الاستعادة.');
      }
    } catch (error) {
      if (mounted) notify(context, authError(error));
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.forum_rounded, size: 76),
                  const SizedBox(height: 14),
                  const Text(
                    'جيران',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'دردشة الجيران عبر الإنترنت',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: hidePassword,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => hidePassword = !hidePassword);
                        },
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? 'يرجى الانتظار...'
                          : registering
                              ? 'إنشاء حساب'
                              : 'تسجيل الدخول',
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => registering = !registering),
                    child: Text(
                      registering
                          ? 'لدي حساب بالفعل'
                          : 'مستخدم جديد؟ أنشئ حسابًا',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : resetPassword,
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('نسيت كلمة المرور؟'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد إعلانات داخل التطبيق.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// PIN محلي لقفل واجهة التطبيق، وليس وسيلة استعادة حساب Firebase.
class PinGate extends StatefulWidget {
  final String uid;
  final Widget child;

  const PinGate({
    super.key,
    required this.uid,
    required this.child,
  });

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  final controller = TextEditingController();
  bool loading = true;
  bool unlocked = false;
  bool creating = false;
  String? savedHash;

  String get storageKey => 'neighbor_pin_${widget.uid}';

  String digest(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(storageKey);

    if (!mounted) return;

    setState(() {
      savedHash = hash;
      creating = hash == null;
      unlocked = hash == null;
      loading = false;
    });
  }

  Future<void> submit() async {
    final pin = controller.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      notify(context, 'يجب إدخال أربعة أرقام.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (creating) {
      await prefs.setString(storageKey, digest(pin));
      if (!mounted) return;

      setState(() {
        savedHash = digest(pin);
        creating = false;
        unlocked = true;
      });

      controller.clear();
      notify(context, 'تم إعداد رمز PIN على هذا الجهاز.');
    } else if (digest(pin) == savedHash) {
      if (!mounted) return;
      setState(() => unlocked = true);
      controller.clear();
    } else {
      controller.clear();
      notify(context, 'رمز PIN غير صحيح.');
    }
  }

  Future<void> changePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    if (!mounted) return;

    setState(() {
      savedHash = null;
      creating = true;
      unlocked = false;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (unlocked) {
      return PinProtectedHome(
        child: widget.child,
        onChangePin: changePin,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('حماية التطبيق')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 64),
                const SizedBox(height: 16),
                Text(
                  creating ? 'أنشئ رمز PIN من أربعة أرقام' : 'أدخل رمز PIN',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                FilledButton(
                  onPressed: submit,
                  child: Text(creating ? 'حفظ الرمز' : 'فتح التطبيق'),
                ),
                if (!creating)
                  TextButton(
                    onPressed: () {
                      notify(
                        context,
                        'PIN محلي فقط. تسجيل الخروج وإعادة تعيين كلمة المرور '
                        'متاحان عبر Firebase.',
                      );
                    },
                    child: const Text('نسيت رمز PIN؟'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PinProtectedHome extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onChangePin;

  const PinProtectedHome({
    super.key,
    required this.child,
    required this.onChangePin,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class MainPage extends StatefulWidget {
  final bool dark;
  final ValueChanged<bool> onThemeChanged;

  const MainPage({
    super.key,
    required this.dark,
    required this.onThemeChanged,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const UsersPage(),
      const StickersPage(),
      const LocalPage(),
      SettingsPage(
        dark: widget.dark,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('جيران')),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'الدردشة',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_emotions_outlined),
            label: 'الملصقات',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching),
            label: 'محلي',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = auth.currentUser!;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('تعذر تحميل المستخدمين. تحقق من قواعد Firestore.'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs
            .where((doc) => doc.id != me.uid)
            .toList();

        if (users.isEmpty) {
          return const Center(
            child: Text('لا يوجد مستخدمون آخرون. أنشئ حسابًا ثانيًا للاختبار.'),
          );
        }

        return ListView.separated(
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = users[index];
            final email = doc.data()['email']?.toString() ?? 'مستخدم';

            return ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline),
              ),
              title: Text(email),
              subtitle: const Text('فتح المحادثة'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      otherUid: doc.id,
                      otherEmail: email,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

String roomId(String a, String b) {
  final ids = [a, b]..sort();
  return '${ids[0]}_${ids[1]}';
}

class ChatPage extends StatefulWidget {
  final String otherUid;
  final String otherEmail;

  const ChatPage({
    super.key,
    required this.otherUid,
    required this.otherEmail,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final textController = TextEditingController();
  bool sending = false;

  String get me => auth.currentUser!.uid;
  String get room => roomId(me, widget.otherUid);

  DocumentReference<Map<String, dynamic>> blockDocument(String owner) {
    return db.collection('blocks').doc(owner)
        .collection('users').doc(owner == me ? widget.otherUid : me);
  }

  Future<bool> isBlocked() async {
    final results = await Future.wait([
      blockDocument(me).get(),
      blockDocument(widget.otherUid).get(),
    ]);
    return results.any((snapshot) => snapshot.exists);
  }

  Future<void> send({
    String? imageUrl,
    String? sticker,
  }) async {
    final text = textController.text.trim();

    if (text.isEmpty && imageUrl == null && sticker == null) return;

    if (sending) return;
    setState(() => sending = true);

    try {
      if (await isBlocked()) {
        if (mounted) notify(context, 'لا يمكن الإرسال؛ يوجد حظر بين الحسابين.');
        return;
      }

      await db.collection('chats').doc(room).collection('messages').add({
        'senderId': me,
        'receiverId': widget.otherUid,
        'text': text,
        'imageUrl': imageUrl,
        'sticker': sticker,
        'createdAt': FieldValue.serverTimestamp(),
      });

      textController.clear();
    } catch (error) {
      if (mounted) notify(context, 'تعذر إرسال الرسالة. تحقق من إعدادات Firebase.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> uploadImage() async {
    try {
      if (await isBlocked()) {
        if (mounted) notify(context, 'لا يمكن الإرسال؛ يوجد حظر بين الحسابين.');
        return;
      }

      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );

      if (selected == null || !mounted) return;

      setState(() => sending = true);

      final file = File(selected.path);
      final ref = storage.ref(
        'chat_media/$room/${DateTime.now().millisecondsSinceEpoch}_$me.jpg',
      );

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await db.collection('chats').doc(room).collection('messages').add({
        'senderId': me,
        'receiverId': widget.otherUid,
        'text': '',
        'imageUrl': url,
        'sticker': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) notify(context, 'تم إرسال الصورة.');
    } catch (error) {
      if (mounted) notify(context, 'تعذر إرسال الصورة. تحقق من Firebase Storage.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> blockUser() async {
    try {
      await blockDocument(me).set({
        'uid': widget.otherUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) notify(context, 'تمت إضافة المستخدم إلى قائمة الحظر.');
    } catch (error) {
      if (mounted) notify(context, 'تعذر الحظر. تحقق من قواعد Firestore.');
    }
  }

  Future<void> unblockUser() async {
    try {
      await blockDocument(me).delete();
      if (mounted) notify(context, 'تم إلغاء الحظر.');
    } catch (error) {
      if (mounted) notify(context, 'تعذر إلغاء الحظر.');
    }
  }

  Future<void> chooseSticker() async {
    const stickers = [
      '😀', '😂', '😍', '🥳',
      '❤️', '👍', '👎', '🙏',
      '🔥', '🌹', '🎉', '👋',
      '😎', '😭', '🤝', '⭐',
    ];

    final sticker = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          children: stickers.map((value) {
            return InkWell(
              onTap: () => Navigator.pop(context, value),
              child: Center(
                child: Text(value, style: const TextStyle(fontSize: 34)),
              ),
            );
          }).toList(),
        ),
      ),
    );

    if (sticker != null) await send(sticker: sticker);
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messageStream = db.collection('chats').doc(room)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(150);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherEmail),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') blockUser();
              if (value == 'unblock') unblockUser();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'block',
                child: Text('حظر المستخدم'),
              ),
              PopupMenuItem(
                value: 'unblock',
                child: Text('إلغاء الحظر'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messageStream.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('تعذر تحميل الرسائل. تحقق من قواعد Firestore.'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(child: Text('ابدأ المحادثة برسالة جديدة.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final mine = data['senderId'] == me;
                    final text = data['text'] as String? ?? '';
                    final sticker = data['sticker'] as String?;
                    final image = data['imageUrl'] as String?;

                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 290),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (text.isNotEmpty) Text(text),
                            if (sticker != null)
                              Text(sticker, style: const TextStyle(fontSize: 36)),
                            if (image != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Image.network(
                                  image,
                                  width: 240,
                                  errorBuilder: (_, __, ___) =>
                                      const Text('تعذر تحميل الصورة'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'إرسال صورة',
                    onPressed: sending ? null : uploadImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: 'الملصقات',
                    onPressed: sending ? null : chooseSticker,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: textController,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => send(),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إرسال',
                    onPressed: sending ? null : () => send(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StickersPage extends StatelessWidget {
  const StickersPage({super.key});

  @override
  Widget build(BuildContext context) {
    const stickers = ['😀', '😂', '😍', '🥳', '❤️', '👍', '🙏', '🔥'];

    return GridView.count(
      padding: const EdgeInsets.all(20),
      crossAxisCount: 4,
      children: stickers.map((sticker) {
        return Card(
          child: Center(
            child: Text(sticker, style: const TextStyle(fontSize: 34)),
          ),
        );
      }).toList(),
    );
  }
}

class LocalPage extends StatelessWidget {
  const LocalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching, size: 64),
            SizedBox(height: 16),
            Text(
              'الدردشة المحلية دون إنترنت',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'الاتصال الفعلي عبر البلوتوث يحتاج إلى إضافة Android مخصصة '
              'وصلاحيات الاتصال واكتشاف الأجهزة. لم يُفعّل في هذه النسخة.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final bool dark;
  final ValueChanged<bool> onThemeChanged;

  const SettingsPage({
    super.key,
    required this.dark,
    required this.onThemeChanged,
  });

  Future<void> resetPassword(BuildContext context) async {
    final email = auth.currentUser?.email;
    if (email == null) return;

    try {
      await auth.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        notify(context, 'أرسلنا رابط الاستعادة إلى بريدك الإلكتروني.');
      }
    } catch (error) {
      if (context.mounted) notify(context, authError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('الحساب'),
          subtitle: Text(user?.email ?? 'غير مسجل'),
        ),
        ListTile(
          leading: const Icon(Icons.lock_reset),
          title: const Text('استعادة كلمة المرور'),
          subtitle: const Text('إرسال رابط إعادة التعيين إلى البريد'),
          onTap: () => resetPassword(context),
        ),
        SwitchListTile(
          value: dark,
          onChanged: onThemeChanged,
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('الوضع الداكن'),
        ),
        ListTile(
          leading: const Icon(Icons.block),
          title: const Text('المستخدمون المحظورون'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BlockedUsersPage(),
              ),
            );
          },
        ),
        const ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('الأمان'),
          subtitle: Text(
            'يُخزّن PIN محليًا على الجهاز. '
            'ليس بديلًا لاستعادة كلمة مرور الحساب.',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () async {
            await auth.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
}

class BlockedUsersPage extends StatelessWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون المحظورون')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('blocks').doc(uid)
            .collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('تعذر تحميل قائمة الحظر. تحقق من قواعد Firestore.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final blocked = snapshot.data!.docs;

          if (blocked.isEmpty) {
            return const Center(child: Text('قائمة الحظر فارغة.'));
          }

          return ListView.builder(
            itemCount: blocked.length,
            itemBuilder: (context, index) {
              final doc = blocked[index];

              return ListTile(
                leading: const Icon(Icons.block),
                title: Text(doc.data()['email']?.toString() ?? doc.id),
                subtitle: Text(doc.id),
                trailing: IconButton(
                  tooltip: 'إلغاء الحظر',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () async {
                    try {
                      await doc.reference.delete();
                      if (context.mounted) notify(context, 'تم إلغاء الحظر.');
                    } catch (_) {
                      if (context.mounted) {
                        notify(context, 'تعذر إلغاء الحظر.');
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}