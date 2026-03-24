import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/identity/identity_service.dart';
import 'core/storage/database.dart';
import 'features/chat/chat_list_screen.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  bool identityReady = false;
  bool dbReady = false;

  try {
    await IdentityService.instance.init();
    identityReady = true;
  } catch (e) {
    debugPrint('Identity init failed: $e');
  }

  try {
    await AppDatabase.instance.init();
    dbReady = true;
  } catch (e) {
    debugPrint('Database init failed: $e');
  }

  runApp(SecureMsgApp(
    identityReady: identityReady,
    dbReady: dbReady,
  ));
}

class SecureMsgApp extends StatelessWidget {
  final bool identityReady;
  final bool dbReady;

  const SecureMsgApp({
    super.key,
    required this.identityReady,
    required this.dbReady,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureMsg',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: identityReady && dbReady
          ? const ChatListScreen()
          : const _ErrorScreen(),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111118),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Color(0xFFE74C3C), size: 56),
              SizedBox(height: 16),
              Text(
                'Startup failed',
                style: TextStyle(
                  color: Color(0xFFEEEEF5),
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Could not initialize security services.\nTry reinstalling the app.',
                style: TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}