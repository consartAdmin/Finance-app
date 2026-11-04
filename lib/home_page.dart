import 'package:flutter/material.dart';

import 'api_service.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'sales_page.dart';
import 'titles_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  /// Abas já abertas (as outras só carregam quando abertas).
  final _opened = <int>{0};

  void _open(int i) => setState(() {
        _tab = i;
        _opened.add(i);
      });

  static const _titles = [
    'Financeiro',
    'Contas a pagar',
    'Contas a receber',
    'Vendas',
  ];

  Future<void> _logout() async {
    await ApiService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(api.userName ?? '',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardPage(onOpen: _open),
          _opened.contains(1)
              ? const TitlesPage(kind: TitleKind.payable)
              : const SizedBox(),
          _opened.contains(2)
              ? const TitlesPage(kind: TitleKind.receivable)
              : const SizedBox(),
          _opened.contains(3) ? const SalesPage() : const SizedBox(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _open,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.call_made), label: 'A pagar'),
          NavigationDestination(
              icon: Icon(Icons.call_received), label: 'A receber'),
          NavigationDestination(
              icon: Icon(Icons.point_of_sale), label: 'Vendas'),
        ],
      ),
    );
  }
}
