import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkSecretaryApp());
}

class WorkSecretaryApp extends StatelessWidget {
  const WorkSecretaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '工作小秘書',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E40AF),
          brightness: Brightness.light,
        ),
      ),
      home: const MainHomePage(),
    );
  }
}

class LogItem {
  final String id;
  final String timestamp;
  final String project;
  final String tag;
  final String content;

  LogItem({
    required this.id,
    required this.timestamp,
    required this.project,
    required this.tag,
    required this.content,
  });

  DateTime get dateTime => DateTime.parse(timestamp);
  String get dateKey => DateFormat('yyyy-MM-dd').format(dateTime);
  String get timeStr => DateFormat('HH:mm').format(dateTime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'project': project,
        'tag': tag,
        'content': content,
      };

  factory LogItem.fromJson(Map<String, dynamic> json) => LogItem(
        id: json['id'],
        timestamp: json['timestamp'],
        project: json['project'],
        tag: json['tag'],
        content: json['content'],
      );
}

class TaskItem {
  final String id;
  String title;
  String project;
  String priority;
  bool isDone;
  final String createdAt;

  TaskItem({
    required this.id,
    required this.title,
    required this.project,
    required this.priority,
    this.isDone = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'project': project,
        'priority': priority,
        'isDone': isDone,
        'createdAt': createdAt,
      };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json['id'],
        title: json['title'],
        project: json['project'] ?? '未分類',
        priority: json['priority'] ?? 'P1',
        isDone: json['isDone'] ?? false,
        createdAt: json['createdAt'],
      );
}

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  int _currentIndex = 0;

  List<LogItem> _logs = [];
  List<TaskItem> _tasks = [];
  List<String> _projects = ['核心專案', '日常營運', '客戶溝通', '個人研發'];
  Map<String, int> _dailyEnergy = {};

  DateTime _selectedDate = DateTime.now();
  String _selectedProject = '核心專案';
  String _selectedTag = '#進度';
  final TextEditingController _logInputCtrl = TextEditingController();

  String _searchKeyword = '';
  String _filterProject = '全部';
  String _filterTag = '全部';

  bool _includeAiPrompt = true;
  bool _exportAllDays = false;

  static const List<String> _tags = ['#進度', '#決策', '#卡點', '#備忘'];
  static const List<String> _priorities = ['P0', 'P1', 'P2', 'P3'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final logsJson = prefs.getStringList('logs_v1') ?? [];
      _logs = logsJson.map((e) => LogItem.fromJson(jsonDecode(e))).toList();

      final tasksJson = prefs.getStringList('tasks_v1') ?? [];
      _tasks = tasksJson.map((e) => TaskItem.fromJson(jsonDecode(e))).toList();

      final savedProjects = prefs.getStringList('projects_v1');
      if (savedProjects != null && savedProjects.isNotEmpty) {
        _projects = savedProjects;
        if (!_projects.contains(_selectedProject)) {
          _selectedProject = _projects.first;
        }
      }

      final energyStr = prefs.getString('energy_v1');
      if (energyStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(energyStr);
        _dailyEnergy = decoded.map((k, v) => MapEntry(k, v as int));
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'logs_v1',
      _logs.map((e) => jsonEncode(e.toJson())).toList(),
    );
    await prefs.setStringList(
      'tasks_v1',
      _tasks.map((e) => jsonEncode(e.toJson())).toList(),
    );
    await prefs.setStringList('projects_v1', _projects);
    await prefs.setString('energy_v1', jsonEncode(_dailyEnergy));
  }

  String get _selectedDateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  void _addLog() {
    final text = _logInputCtrl.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final recordTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );

    final newLog = LogItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: recordTime.toIso8601String(),
      project: _selectedProject,
      tag: _selectedTag,
      content: text,
    );

    setState(() {
      _logs.add(newLog);
      _logInputCtrl.clear();
    });
    _saveData();
  }

  void _convertLogToTask(LogItem log) {
    String chosenPriority = 'P1';
    final titleCtrl = TextEditingController(text: log.content);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('轉為待辦事項'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '待辦內容',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Text('選擇優先級：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _priorities.map((p) {
                  return ChoiceChip(
                    label: Text(p),
                    selected: chosenPriority == p,
                    onSelected: (_) => setDialogState(() => chosenPriority = p),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                setState(() {
                  _tasks.add(TaskItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleCtrl.text.trim(),
                    project: log.project,
                    priority: chosenPriority,
                    createdAt: DateTime.now().toIso8601String(),
                  ));
                });
                _saveData();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已加入 [$chosenPriority] 待辦事項！')),
                );
              },
              child: const Text('確認新增'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProjectDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增專案 / 領域分類'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：產品開發、家庭事務、投資研究',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty && !_projects.contains(name)) {
                setState(() {
                  _projects.add(name);
                  _selectedProject = name;
                });
                _saveData();
              }
              Navigator.pop(ctx);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog() {
    final titleCtrl = TextEditingController();
    String priority = 'P1';
    String project = _selectedProject;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新增待辦事項'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '任務名稱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: project,
                  decoration: const InputDecoration(
                    labelText: '所屬專案',
                    border: OutlineInputBorder(),
                  ),
                  items: _projects
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => project = v);
                  },
                ),
                const SizedBox(height: 12),
                const Text('優先級 (P0 最高 → P3 最低)：'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: _priorities.map((p) {
                    return ChoiceChip(
                      label: Text(p),
                      selected: priority == p,
                      onSelected: (_) => setDialogState(() => priority = p),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = titleCtrl.text.trim();
                if (text.isEmpty) return;
                setState(() {
                  _tasks.add(TaskItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: text,
                    project: project,
                    priority: priority,
                    createdAt: DateTime.now().toIso8601String(),
                  ));
                });
                _saveData();
                Navigator.pop(ctx);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  String _buildNotebookMarkdown() {
    final targetLogs = _exportAllDays
        ? List<LogItem>.from(_logs)
        : _logs.where((l) => l.dateKey == _selectedDateKey).toList();

    targetLogs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final completedTasks = _tasks.where((t) => t.isDone).toList();
    final pendingTasks = _tasks.where((t) => !t.isDone).toList();
    pendingTasks.sort((a, b) => a.priority.compareTo(b.priority));

    final energy = _dailyEnergy[_selectedDateKey] ?? 4;

    final sb = StringBuffer();
    if (_exportAllDays) {
      sb.writeln('# 跨日工作總覽日誌 | 導出日期：$_selectedDateKey');
    } else {
      sb.writeln('# 每日工作覆盤日誌 | 日期：$_selectedDateKey');
    }
    sb.writeln('---');
    sb.writeln('## 一、 核心狀態與數據概覽');
    if (!_exportAllDays) {
      sb.writeln('- 當日精力與專注指數：$energy / 5 顆星');
    }
    sb.writeln('- 紀錄事件數：${targetLogs.length} 筆');
    sb.writeln('- 待辦完成進度：已完成 ${completedTasks.length} 項 / 未完成 ${pendingTasks.length} 項');
    sb.writeln('');

    sb.writeln('## 二、 工作時間軸與脈絡 (Timeline & Context)');
    if (targetLogs.isEmpty) {
      sb.writeln('- （尚無日誌紀錄）');
    } else {
      for (final log in targetLogs) {
        final timePrefix = _exportAllDays ? '${log.dateKey} ${log.timeStr}' : log.timeStr;
        sb.writeln('- [$timePrefix] 【${log.project}】${log.tag} ${log.content}');
      }
    }
    sb.writeln('');

    sb.writeln('## 三、 未完成待辦與優先級排程 (Pending Tasks)');
    if (pendingTasks.isEmpty) {
      sb.writeln('- （目前無未完成待辦事項）');
    } else {
      for (final task in pendingTasks) {
        sb.writeln('- [${task.priority}] 【${task.project}】${task.title}');
      }
    }
    sb.writeln('');

    if (completedTasks.isNotEmpty) {
      sb.writeln('## 四、 已完成事項備查 (Completed)');
      for (final task in completedTasks) {
        sb.writeln('- [x] [${task.priority}] 【${task.project}】${task.title}');
      }
      sb.writeln('');
    }

    if (_includeAiPrompt) {
      sb.writeln('---');
      sb.writeln('## 五、 給 NotebookLM 的首席幕僚分析指令');
      sb.writeln('> 請根據以上工作日誌與待辦清單，扮演我的「專案幕僚與效率顧問」，提供以下回饋：');
      sb.writeln('> 1. **盲點與風險偵測**：檢視今日的 `#卡點` 與 `#決策`，是否有潛在風險或更省力的解法？');
      sb.writeln('> 2. **明日排程優化**：根據未完成的 `P0` 與 `P1` 待辦事項，建議我明天早上第一件事該從哪裡著手？');
      sb.writeln('> 3. **關鍵備忘提煉**：將 `#備忘` 與零散進度整理成結構化重點，方便未來回溯。');
    }

    return sb.toString();
  }

  Color _tagColor(String tag) {
    switch (tag) {
      case '#進度':
        return Colors.blue.shade700;
      case '#決策':
        return Colors.purple.shade700;
      case '#卡點':
        return Colors.red.shade700;
      case '#備忘':
        return Colors.teal.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'P0':
        return Colors.red.shade700;
      case 'P1':
        return Colors.orange.shade800;
      case 'P2':
        return Colors.blue.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDailyLogTab(),
      _buildTaskTab(),
      _buildSearchTab(),
      _buildExportTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作小秘書 (NotebookLM 伴侶)', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '新增專案分類',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _showAddProjectDialog,
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_note), label: '今日日誌'),
          NavigationDestination(icon: Icon(Icons.task_alt), label: '待辦優先級'),
          NavigationDestination(icon: Icon(Icons.manage_search), label: '專案檢索'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI 導出'),
        ],
      ),
    );
  }

  Widget _buildDailyLogTab() {
    final dayLogs = _logs.where((l) => l.dateKey == _selectedDateKey).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final currentEnergy = _dailyEnergy[_selectedDateKey] ?? 4;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_selectedDateKey),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
              const Spacer(),
              const Text('今日精力：', style: TextStyle(fontSize: 13)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return InkWell(
                    onTap: () {
                      setState(() => _dailyEnergy[_selectedDateKey] = star);
                      _saveData();
                    },
                    child: Icon(
                      star <= currentEnergy ? Icons.bolt : Icons.bolt_outlined,
                      color: star <= currentEnergy ? Colors.amber.shade700 : Colors.grey,
                      size: 22,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: dayLogs.isEmpty
              ? const Center(
                  child: Text(
                    '今天還沒有工作紀錄\n在下方輸入框隨時記下進度、決策或靈感吧！',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: dayLogs.length,
                  itemBuilder: (ctx, i) {
                    final log = dayLogs[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(
                          log.timeStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                        title: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '【${log.project}】',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _tagColor(log.tag).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                log.tag,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _tagColor(log.tag),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            log.content,
                            style: const TextStyle(fontSize: 15, color: Colors.black87),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '轉為待辦事項',
                              icon: const Icon(Icons.add_task, color: Colors.blue),
                              onPressed: () => _convertLogToTask(log),
                            ),
                            IconButton(
                              tooltip: '刪除',
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
                              onPressed: () {
                                setState(() => _logs.removeWhere((e) => e.id == log.id));
                                _saveData();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: _selectedProject,
                      underline: const SizedBox(),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      items: _projects
                          .map((p) => DropdownMenuItem(value: p, child: Text('📁 $p')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedProject = v);
                      },
                    ),
                    const SizedBox(width: 8),
                    ..._tags.map((tag) {
                      final isSelected = _selectedTag == tag;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(tag),
                          selected: isSelected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _selectedTag = tag),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _logInputCtrl,
                      decoration: InputDecoration(
                        hintText: '輸入 $_selectedProject 的 $_selectedTag 紀錄...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _addLog(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addLog,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('記錄'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskTab() {
    final sortedTasks = List<TaskItem>.from(_tasks)
      ..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        return a.priority.compareTo(b.priority);
      });

    return Scaffold(
      body: sortedTasks.isEmpty
          ? const Center(
              child: Text('目前沒有待辦事項\n點擊右下角按鈕或從日誌轉入待辦！', textAlign: TextAlign.center),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sortedTasks.length,
              itemBuilder: (ctx, i) {
                final task = sortedTasks[i];
                return Card(
                  child: ListTile(
                    leading: Checkbox(
                      value: task.isDone,
                      onChanged: (v) {
                        setState(() => task.isDone = v ?? false);
                        _saveData();
                      },
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration: task.isDone ? TextDecoration.lineThrough : null,
                        color: task.isDone ? Colors.grey : Colors.black87,
                        fontWeight: task.priority == 'P0' && !task.isDone
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('專案：${task.project}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _priorityColor(task.priority).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            task.priority,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _priorityColor(task.priority),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => _tasks.removeWhere((t) => t.id == task.id));
                            _saveData();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        icon: const Icon(Icons.add),
        label: const Text('新增待辦'),
      ),
    );
  }

  Widget _buildSearchTab() {
    final filteredLogs = _logs.where((log) {
      final matchProject = _filterProject == '全部' || log.project == _filterProject;
      final matchTag = _filterTag == '全部' || log.tag == _filterTag;
      final matchKeyword = _searchKeyword.isEmpty ||
          log.content.toLowerCase().contains(_searchKeyword.toLowerCase()) ||
          log.project.toLowerCase().contains(_searchKeyword.toLowerCase());
      return matchProject && matchTag && matchKeyword;
    }).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '搜尋關鍵字（決策、卡點、專案內容）...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchKeyword = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filterProject,
                      decoration: const InputDecoration(
                        labelText: '專案過濾',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ['全部', ..._projects]
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _filterProject = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filterTag,
                      decoration: const InputDecoration(
                        labelText: '標籤過濾',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ['全部', ..._tags]
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _filterTag = v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredLogs.isEmpty
              ? const Center(child: Text('找不到符合條件的歷史紀錄'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filteredLogs.length,
                  itemBuilder: (ctx, i) {
                    final log = filteredLogs[i];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${log.dateKey} ${log.timeStr}  【${log.project}】 ${log.tag}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _tagColor(log.tag),
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(log.content, style: const TextStyle(fontSize: 15)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExportTab() {
    final markdownText = _buildNotebookMarkdown();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('附上 NotebookLM 首席幕僚分析指令'),
                    subtitle: const Text('在文末自動加入引導 AI 進行盲點分析與排程建議的提問詞'),
                    value: _includeAiPrompt,
                    onChanged: (v) => setState(() => _includeAiPrompt = v),
                  ),
                  SwitchListTile(
                    title: const Text('導出全部歷史日誌（跨日彙整模式）'),
                    subtitle: Text(_exportAllDays ? '目前：包含所有日期的紀錄' : '目前：僅導出 $_selectedDateKey 當日紀錄'),
                    value: _exportAllDays,
                    onChanged: (v) => setState(() => _exportAllDays = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: markdownText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已複製 Markdown！可直接貼入 NotebookLM')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('一鍵複製全文'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Share.share(markdownText, subject: '每日工作覆盤日誌_$_selectedDateKey');
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('分享 / 存入雲端'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('NotebookLM 結構化預覽：', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  markdownText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}