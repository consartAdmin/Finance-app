import 'package:flutter/material.dart';

import 'api_service.dart';
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

  static const _titles = ['Contas a pagar', 'Contas a receber', 'Vendas'];

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
        children: const [
          TitlesPage(kind: TitleKind.payable),
          TitlesPage(kind: TitleKind.receivable),
          SalesPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
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
