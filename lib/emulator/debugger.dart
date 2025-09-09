class Debugger {
  static final Debugger _instance = Debugger._internal();

  factory Debugger() {
    return _instance;
  }

  Debugger._internal();

  List<String> logs = [];

  void addLog(String log) {
    logs.add(log);
  }

  List<String> getLogs() {
    return logs;
  }

  void clearLogs() {
    logs.clear();
  }
}
