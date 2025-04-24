import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Hive.initFlutter();
  await Hive.openBox('sobriety_data');
  await Hive.openBox('consumption_logs');
  
  runApp(
    ChangeNotifierProvider(
      create: (context) => SobrietyModel(),
      child: const WellApp(),
    ),
  );
}

class WellApp extends StatelessWidget {
  const WellApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Well - Sobriety Tracker',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _showDailyReminder = false;
  DateTime? _lastReminderDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForReminder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForReminder();
    }
  }

  void _checkForReminder() {
    final now = DateTime.now();
    final lastReminderBox = Hive.box('sobriety_data');
    _lastReminderDate = DateTime.tryParse(lastReminderBox.get('last_reminder_date', defaultValue: '') ?? '');
    
    // Check if it's a new day and after 9 AM
    final isAfter9AM = now.hour >= 9;
    final isNewDay = _lastReminderDate == null || 
                     !_isSameDay(_lastReminderDate!, now);
    
    if (isAfter9AM && isNewDay) {
      setState(() {
        _showDailyReminder = true;
      });
      lastReminderBox.put('last_reminder_date', now.toIso8601String());
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _dismissReminder() {
    setState(() {
      _showDailyReminder = false;
    });
  }

  final List<Widget> _pages = [
    const TimerPage(),
    const WatchPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Well - Sobriety Tracker'),
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_showDailyReminder)
            GestureDetector(
              onTap: _dismissReminder,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.teal,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Start your day strong. Tap to track your sobriety.",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _dismissReminder,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _pages[_currentIndex],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.timer),
            label: 'Timer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Watch',
          ),
        ],
      ),
    );
  }
}

class SobrietyModel extends ChangeNotifier {
  DateTime? _startTime;
  int _temptationCount = 0;
  int _slipCount = 0;
  bool _timerActive = false;
  final _box = Hive.box('sobriety_data');
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  
  SobrietyModel() {
    _loadData();
    _startTimer();
  }
  
  void _loadData() {
    final startTimeStr = _box.get('start_time');
    if (startTimeStr != null) {
      _startTime = DateTime.parse(startTimeStr);
    }
    
    _temptationCount = _box.get('temptation_count', defaultValue: 0);
    _slipCount = _box.get('slip_count', defaultValue: 0);
    _timerActive = _box.get('timer_active', defaultValue: false);
    
    if (_startTime != null && _timerActive) {
      _calculateElapsed();
    }
  }
  
  void _calculateElapsed() {
    if (_startTime != null && _timerActive) {
      _elapsed = DateTime.now().difference(_startTime!);
    }
  }
  
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerActive) {
        _calculateElapsed();
        notifyListeners();
      }
    });
  }
  
  void start() {
    if (_startTime == null || !_timerActive) {
      _startTime = DateTime.now();
      _timerActive = true;
      _box.put('start_time', _startTime!.toIso8601String());
      _box.put('timer_active', _timerActive);
      notifyListeners();
    }
  }
  
  void logTemptation() {
    _temptationCount++;
    _box.put('temptation_count', _temptationCount);
    notifyListeners();
  }
  
  void logSlip() {
    _slipCount++;
    _box.put('slip_count', _slipCount);
    
    // Pause timer
    _timerActive = false;
    _box.put('timer_active', _timerActive);
    
    // Reset if 3 slips
    if (_slipCount >= 3) {
      reset();
    } else {
      notifyListeners();
    }
  }
  
  void reset() {
    _startTime = null;
    _slipCount = 0;
    _temptationCount = 0;
    _timerActive = false;
    _elapsed = Duration.zero;
    
    _box.put('start_time', null);
    _box.put('slip_count', _slipCount);
    _box.put('temptation_count', _temptationCount);
    _box.put('timer_active', _timerActive);
    
    notifyListeners();
  }
  
  Duration get elapsed {
    if (_startTime == null || !_timerActive) {
      return _elapsed;
    }
    return DateTime.now().difference(_startTime!);
  }
  
  String get formattedTime {
    final duration = elapsed;
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    
    if (days > 0) {
      return '$days days, $hours hours, $minutes mins';
    } else if (hours > 0) {
      return '$hours hours, $minutes mins';
    } else {
      return '$minutes mins';
    }
  }
  
  bool get isActive => _timerActive;
  int get temptationCount => _temptationCount;
  int get slipCount => _slipCount;
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class TimerPage extends StatelessWidget {
  const TimerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SobrietyModel>(
      builder: (context, model, child) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                margin: const EdgeInsets.symmetric(vertical: 20),
                color: const Color(0xFF1E1E1E),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'SOBER TIME',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        model.formattedTime,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              const Text('TEMPTATIONS'),
                              const SizedBox(height: 5),
                              Text(
                                '${model.temptationCount}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 40),
                          Column(
                            children: [
                              const Text('SLIPS'),
                              const SizedBox(height: 5),
                              Text(
                                '${model.slipCount}/3',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: model.slipCount > 0 ? Colors.amber : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (!model.isActive)
                ElevatedButton(
                  onPressed: () => model.start(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    minimumSize: const Size(200, 60),
                  ),
                  child: const Text(
                    'START',
                    style: TextStyle(fontSize: 24),
                  ),
                ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => model.logTemptation(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[800],
                    ),
                    child: const Text('TEMPTATION'),
                  ),
                  ElevatedButton(
                    onPressed: () => model.logSlip(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('SLIP'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => model.reset(),
                child: const Text('Reset Timer'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ConsumptionLog {
  final String type;
  final DateTime date;
  final String notes;
  
  ConsumptionLog({
    required this.type,
    required this.date,
    this.notes = '',
  });
  
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'date': date.toIso8601String(),
      'notes': notes,
    };
  }
  
  factory ConsumptionLog.fromJson(Map<String, dynamic> json) {
    return ConsumptionLog(
      type: json['type'],
      date: DateTime.parse(json['date']),
      notes: json['notes'] ?? '',
    );
  }
}

class WatchPage extends StatefulWidget {
  const WatchPage({Key? key}) : super(key: key);

  @override
  _WatchPageState createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  final _logBox = Hive.box('consumption_logs');
  final _typeController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  
  List<ConsumptionLog> _logs = [];
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }
  
  void _loadLogs() {
    final logsJson = _logBox.values.toList();
    setState(() {
      _logs = logsJson.map((log) => ConsumptionLog.fromJson(Map<String, dynamic>.from(log))).toList();
      _logs.sort((a, b) => b.date.compareTo(a.date)); // Sort newest first
    });
  }
  
  void _addLog() {
    if (_typeController.text.isEmpty) return;
    
    final log = ConsumptionLog(
      type: _typeController.text,
      date: _selectedDate,
      notes: _notesController.text,
    );
    
    _logBox.add(log.toJson());
    _loadLogs();
    
    _typeController.clear();
    _notesController.clear();
    Navigator.pop(context);
  }
  
  void _showAddLogDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Consumption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _typeController,
              decoration: const InputDecoration(
                labelText: 'Type (Alcohol, Drug, etc.)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              title: Text(DateFormat('MMMM d, y').format(_selectedDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: _addLog,
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Consumption Log',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('No logs yet. Add your first log.'),
                  )
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(log.type),
                          subtitle: Text(log.notes.isNotEmpty ? log.notes : 'No notes'),
                          trailing: Text(DateFormat('MMM d, y').format(log.date)),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('ADD LOG'),
                onPressed: _showAddLogDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _typeController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
