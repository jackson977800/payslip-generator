import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/database.dart';
import 'screens/dashboard.dart';
import 'screens/employees.dart';
import 'screens/history.dart';
import 'screens/payroll.dart';
import 'screens/settings.dart';
import 'services.dart';
import 'theme.dart';

/// 全局状态：数据库、服务层、SMTP 授权码（存在系统安全存储里）
class AppState extends ChangeNotifier {
  final AppDatabase db = AppDatabase();
  late final Services services = Services(db);
  final _secure = const FlutterSecureStorage();

  bool ready = false;

  Future<void> init() async {
    await db.db; // 触发建表与默认设置
    ready = true;
    notifyListeners();
  }

  /// SMTP 授权码存在 Android Keystore（对应桌面版的 Windows DPAPI）——
  /// 换设备或数据被拷走都拿不到。
  Future<String> smtpPassword() async =>
      await _secure.read(key: 'smtp_password') ?? '';

  Future<void> setSmtpPassword(String v) async {
    if (v.isEmpty) {
      await _secure.delete(key: 'smtp_password');
    } else {
      await _secure.write(key: 'smtp_password', value: v);
    }
  }
}

final appState = AppState();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PayslipApp());
}

class PayslipApp extends StatelessWidget {
  const PayslipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Payslip Generator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _refreshToken = 0;

  @override
  void initState() {
    super.initState();
    appState.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  void bumpRefresh() => setState(() => _refreshToken++);

  @override
  Widget build(BuildContext context) {
    if (!appState.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = [
      DashboardScreen(
          onNavigate: (i) => setState(() => _index = i),
          refreshToken: _refreshToken),
      EmployeesScreen(refreshToken: _refreshToken, onChanged: bumpRefresh),
      PayrollScreen(refreshToken: _refreshToken, onChanged: bumpRefresh),
      HistoryScreen(refreshToken: _refreshToken, onChanged: bumpRefresh),
      SettingsScreen(onChanged: bumpRefresh),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payslip Generator'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: bumpRefresh,
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Staff'),
          NavigationDestination(
              icon: Icon(Icons.calculate_outlined),
              selectedIcon: Icon(Icons.calculate),
              label: 'Payroll'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
