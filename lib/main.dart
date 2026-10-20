import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

String nowStr() => DateTime.now().toString().substring(0, 16);
String bs(double v) => 'Bs ${v.toStringAsFixed(2)}';
double parseNum(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

// ───────────── MODELOS ─────────────
class Person {
  final String id;
  String name;
  double garantia; // ahorro / garantía depositada en la app
  Person(this.id, this.name, this.garantia);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'g': garantia};
  factory Person.fromJson(Map<String, dynamic> j) =>
      Person(j['id'], j['name'], (j['g'] as num).toDouble());
}

class Rec {
  final int round;
  final String pid;
  final double amount;
  final String type; // 'cuota' | 'garantia'
  final String date;
  Rec(this.round, this.pid, this.amount, this.type, this.date);
  Map<String, dynamic> toJson() =>
      {'r': round, 'p': pid, 'a': amount, 't': type, 'd': date};
  factory Rec.fromJson(Map<String, dynamic> j) =>
      Rec(j['r'], j['p'], (j['a'] as num).toDouble(), j['t'], j['d']);
}

class Mov {
  final String date, text;
  final double amount;
  Mov(this.date, this.text, this.amount);
  Map<String, dynamic> toJson() => {'d': date, 't': text, 'a': amount};
  factory Mov.fromJson(Map<String, dynamic> j) =>
      Mov(j['d'], j['t'], (j['a'] as num).toDouble());
}

class Group {
  final String id;
  String name, periodo;
  double cuota, garantiaMin;
  List<Person> people = [];
  List<String> order = [];
  int round = 0;
  List<Rec> recs = [];
  List<Mov> movs = [];

  Group(this.id, this.name, this.periodo, this.cuota, this.garantiaMin);

  Person person(String id) => people.firstWhere((p) => p.id == id);
  bool get started => round > 0 || recs.isNotEmpty;
  bool get finished => order.isNotEmpty && round >= order.length;
  bool paid(String pid) => recs.any((r) => r.round == round && r.pid == pid);
  double get pozo =>
      recs.where((r) => r.round == round).fold(0.0, (a, r) => a + r.amount);
  double get esperado => cuota * people.length;
  int get pagaron => people.where((p) => paid(p.id)).length;
  void note(String t, double a) => movs.add(Mov(nowStr(), t, a));

  void addPerson(String name, double deposito) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    people.add(Person(id, name, deposito));
    order.add(id);
    note('$name ingresó y depositó su garantía', deposito);
  }

  void addSavings(Person p, double amount) {
    p.garantia += amount;
    note('${p.name} agregó ahorro a su garantía', amount);
  }

  void pay(Person p) {
    if (paid(p.id)) return;
    recs.add(Rec(round, p.id, cuota, 'cuota', nowStr()));
    note('${p.name} pagó su cuota (ronda ${round + 1})', cuota);
  }

  void closeRound() {
    final r = round;
    for (final p in people) {
      if (!paid(p.id)) {
        final d = min(cuota, p.garantia);
        p.garantia -= d;
        recs.add(Rec(r, p.id, d, 'garantia', nowStr()));
        note(
            'Garantía de ${p.name} cubrió su cuota (ronda ${r + 1})' +
                (d < cuota ? ' - PARCIAL, en mora' : ''),
            d);
      }
    }
    final receptor = person(order[r]);
    note('Pozo entregado a ${receptor.name} (ronda ${r + 1})', pozo);
    round++;
    if (finished) {
      var t = 0.0;
      for (final p in people) {
        t += p.garantia;
        p.garantia = 0;
      }
      note('Ciclo terminado: garantías restantes devueltas', t);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'periodo': periodo,
        'cuota': cuota,
        'gmin': garantiaMin,
        'people': people.map((e) => e.toJson()).toList(),
        'order': order,
        'round': round,
        'recs': recs.map((e) => e.toJson()).toList(),
        'movs': movs.map((e) => e.toJson()).toList(),
      };
  factory Group.fromJson(Map<String, dynamic> j) {
    final g = Group(j['id'], j['name'], j['periodo'],
        (j['cuota'] as num).toDouble(), (j['gmin'] as num).toDouble());
    g.people = (j['people'] as List)
        .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    g.order = List<String>.from(j['order']);
    g.round = j['round'];
    g.recs = (j['recs'] as List)
        .map((e) => Rec.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    g.movs = (j['movs'] as List)
        .map((e) => Mov.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return g;
  }
}

// ───────────── ESTADO ─────────────
class AppState extends ChangeNotifier {
  String? user, pass;
  bool logged = false;
  List<Group> groups = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    user = p.getString('user');
    pass = p.getString('pass');
    final s = p.getString('groups');
    if (s != null) {
      groups = (jsonDecode(s) as List)
          .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('groups', jsonEncode(groups.map((g) => g.toJson()).toList()));
    notifyListeners();
  }

  Future<void> register(String u, String pw) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('user', u);
    await p.setString('pass', pw);
    user = u;
    pass = pw;
    logged = true;
    notifyListeners();
  }

  bool login(String u, String pw) {
    if (u == user && pw == pass) {
      logged = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    logged = false;
    notifyListeners();
  }
}
// ───────────── UI ─────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (d) => Material(
      color: Colors.white,
      child: SingleChildScrollView(
          child: Text('ERROR: ${d.exception}',
              style: const TextStyle(color: Colors.red, fontSize: 16))));
  runApp(const Boot());
}

class Boot extends StatelessWidget {
  const Boot({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: FutureBuilder<AppState>(
          future: () async {
            final s = AppState();
            await s.load();
            return s;
          }(),
          builder: (c, snap) {
            if (snap.hasError) {
              return Scaffold(
                  body: SafeArea(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Text('ERROR: ${snap.error}',
                              style: const TextStyle(color: Colors.red)))));
            }
            if (!snap.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return AyniApp(snap.data!);
          },
        ),
      );
}

const kNavy = Color(0xFF2B3A4A);
const kTerra = Color(0xFFC0654A);

class AyniApp extends StatelessWidget {
  final AppState st;
  const AyniApp(this.st, {super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AyniApp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kTerra, primary: kTerra),
          appBarTheme: const AppBarTheme(
              backgroundColor: kNavy, foregroundColor: Colors.white),
        ),
        home: AnimatedBuilder(
          animation: st,
          builder: (_, __) => st.logged ? HomePage(st) : LoginPage(st),
        ),
      );
}

void msg(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

Future<List<String>?> form(BuildContext c, String title, List<String> labels,
    {List<String>? init, List<bool>? numeric}) {
  final ctrls = [
    for (var i = 0; i < labels.length; i++)
      TextEditingController(text: init != null ? init[i] : '')
  ];
  return showDialog<List<String>>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            TextField(
              controller: ctrls[i],
              decoration: InputDecoration(labelText: labels[i]),
              keyboardType: (numeric != null && numeric[i])
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () =>
                Navigator.pop(d, ctrls.map((e) => e.text.trim()).toList()),
            child: const Text('Aceptar')),
      ],
    ),
  );
}

class LoginPage extends StatefulWidget {
  final AppState st;
  const LoginPage(this.st, {super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final u = TextEditingController();
  final p = TextEditingController();
  String? err;

  @override
  Widget build(BuildContext context) {
    final reg = widget.st.user == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              const Icon(Icons.groups_2, size: 80, color: kTerra),
              const SizedBox(height: 8),
              Text('AyniApp',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontWeight: FontWeight.bold, color: kNavy)),
              const Text('Pasanaku digital con garantía'),
              const SizedBox(height: 28),
              TextField(
                  controller: u,
                  decoration: const InputDecoration(
                      labelText: 'Usuario', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: p,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Contraseña', border: OutlineInputBorder())),
              if (err != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(err!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final us = u.text.trim(), pw = p.text;
                    if (us.isEmpty || pw.isEmpty) {
                      setState(() => err = 'Completa usuario y contraseña');
                    } else if (reg) {
                      await widget.st.register(us, pw);
                    } else if (!widget.st.login(us, pw)) {
                      setState(() => err = 'Usuario o contraseña incorrectos');
                    }
                  },
                  child: Text(reg ? 'Crear cuenta' : 'Ingresar'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final AppState st;
  const HomePage(this.st, {super.key});

  Future<void> _new(BuildContext c) async {
    final r = await form(
        c,
        'Nuevo pasanaku',
        [
          'Nombre del pasanaku',
          'Cuota por periodo (Bs)',
          'Periodo (Diario/Semanal/Mensual)',
          'Garantía mínima para participar (Bs)'
        ],
        init: ['', '200', 'Mensual', '1000'],
        numeric: [false, true, false, true]);
    if (r == null) return;
    final cuota = parseNum(r[1]);
    if (r[0].isEmpty || cuota <= 0) {
      if (c.mounted) msg(c, 'Ingresa un nombre y una cuota válida');
      return;
    }
    st.groups.add(Group(DateTime.now().microsecondsSinceEpoch.toString(), r[0],
        r[2].isEmpty ? 'Mensual' : r[2], cuota, parseNum(r[3])));
    await st.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis pasanakus'), actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
              onPressed: st.logout)
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _new(context),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo')),
        body: st.groups.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                        'Aún no tienes pasanakus.\nToca "Nuevo" para crear uno.',
                        textAlign: TextAlign.center)))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final g in st.groups)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: kNavy,
                            child: Icon(Icons.savings, color: Colors.white)),
                        title: Text(g.name),
                        subtitle: Text(
                            '${bs(g.cuota)} • ${g.periodo} • ${g.people.length} participantes'
                            '${g.finished ? ' • Finalizado' : ''}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => GroupPage(st, g.id))),
                      ),
                    ),
                ],
              ),
      );
}

class GroupPage extends StatelessWidget {
  final AppState st;
  final String gid;
  const GroupPage(this.st, this.gid, {super.key});

  Future<void> _add(BuildContext c, Group g) async {
    final r = await form(
        c,
        'Nuevo participante',
        ['Nombre completo', 'Ahorro a depositar (mín. ${bs(g.garantiaMin)})'],
        init: ['', g.garantiaMin.toStringAsFixed(0)],
        numeric: [false, true]);
    if (r == null || r[0].isEmpty) return;
    final amt = parseNum(r[1]);
    if (amt < g.garantiaMin) {
      if (c.mounted) {
        msg(c, 'Debe depositar al menos ${bs(g.garantiaMin)} para participar');
      }
      return;
    }
    g.addPerson(r[0], amt);
    await st.save();
  }

  Future<void> _savings(BuildContext c, Group g, Person p) async {
    final r = await form(c, 'Agregar ahorro a ${p.name}', ['Monto (Bs)'],
        numeric: [true]);
    if (r == null) return;
    final a = parseNum(r[0]);
    if (a <= 0) return;
    g.addSavings(p, a);
    await st.save();
  }

  Future<void> _close(BuildContext c, Group g) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Cerrar ronda'),
        content: Text(
            'Se entregará el pozo a ${g.person(g.order[g.round]).name}. '
            'Quienes no pagaron serán cubiertos con su garantía.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cerrar ronda')),
        ],
      ),
    );
    if (ok == true) {
      g.closeRound();
      await st.save();
    }
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: st,
        builder: (_, __) {
          final g = st.groups.firstWhere((x) => x.id == gid);
          return DefaultTabController(
            length: 4,
            child: Scaffold(
              appBar: AppBar(
                title: Text(g.name),
                bottom: const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(text: 'Resumen'),
                    Tab(text: 'Personas'),
                    Tab(text: 'Turnos'),
                    Tab(text: 'Historial')
                  ],
                ),
              ),
              floatingActionButton: g.started
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => _add(c, g),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Participante')),
              body: TabBarView(children: [
                _resumen(c, g),
                _personas(c, g),
                _turnos(g),
                _historial(g),
              ]),
            ),
          );
        },
      );

  Widget _resumen(BuildContext c, Group g) {
    final n = g.order.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                g.finished
                    ? 'Ciclo completado ✔'
                    : n == 0
                        ? 'Agrega participantes para comenzar'
                        : 'Ronda ${g.round + 1} de $n',
                style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Cuota: ${bs(g.cuota)} • ${g.periodo}'),
            Text('Garantía mínima: ${bs(g.garantiaMin)}'),
            if (!g.finished && n > 0) ...[
              const SizedBox(height: 8),
              Text('Recibe el pozo: ${g.person(g.order[g.round]).name}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Pozo: ${bs(g.pozo)} de ${bs(g.esperado)}'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: g.esperado > 0 ? g.pozo / g.esperado : 0,
                  minHeight: 10),
              const SizedBox(height: 6),
              Text('Pagaron: ${g.pagaron} de ${g.people.length}'),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (!g.started && n > 1)
        OutlinedButton.icon(
            onPressed: () async {
              g.order.shuffle(Random());
              await st.save();
              if (c.mounted) msg(c, 'Orden de turnos sorteado');
            },
            icon: const Icon(Icons.casino),
            label: const Text('Sortear orden de turnos')),
      if (!g.finished && n > 1)
        FilledButton.icon(
            onPressed: () => _close(c, g),
            icon: const Icon(Icons.flag),
            label: const Text('Cerrar ronda y entregar pozo')),
    ]);
  }

  Widget _personas(BuildContext c, Group g) {
    if (g.people.isEmpty) {
      return const Center(child: Text('Sin participantes todavía'));
    }
    return ListView(children: [
      for (final p in g.people)
        ListTile(
          leading: CircleAvatar(
              backgroundColor: g.paid(p.id) ? Colors.green : kNavy,
              child: Icon(g.paid(p.id) ? Icons.check : Icons.person,
                  color: Colors.white)),
          title: Text(p.name),
          subtitle: Text(
              'Ahorro/garantía: ${bs(p.garantia)}'
              '${p.garantia < g.cuota ? '  ⚠ menor a 1 cuota' : ''}\n'
              '${g.paid(p.id) ? 'Pagó esta ronda' : 'Pago pendiente'}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'pay') {
                g.pay(p);
                await st.save();
              } else {
                await _savings(c, g, p);
              }
            },
            itemBuilder: (_) => [
              if (!g.paid(p.id) && !g.finished && g.people.length > 1)
                const PopupMenuItem(value: 'pay', child: Text('Registrar pago de cuota')),
              const PopupMenuItem(value: 'save', child: Text('Agregar ahorro')),
            ],
          ),
        ),
    ]);
  }

  Widget _turnos(Group g) {
    if (g.order.isEmpty) return const Center(child: Text('Sin turnos todavía'));
    return ListView(children: [
      for (var i = 0; i < g.order.length; i++)
        ListTile(
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text(g.person(g.order[i]).name),
          tileColor: (i == g.round && !g.finished) ? Colors.orange.shade50 : null,
          trailing: i < g.round
              ? const Icon(Icons.check_circle, color: Colors.green)
              : (i == g.round && !g.finished)
                  ? const Text('Turno actual')
                  : null,
        ),
    ]);
  }

  Widget _historial(Group g) {
    if (g.movs.isEmpty) return const Center(child: Text('Sin registros todavía'));
    final list = g.movs.reversed.toList();
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => ListTile(
        title: Text(list[i].text),
        subtitle: Text(list[i].date),
        trailing: Text(bs(list[i].amount),
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
