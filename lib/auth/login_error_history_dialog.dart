import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'login_diagnostics.dart';

class LoginErrorHistoryDialog extends StatefulWidget {
  const LoginErrorHistoryDialog({super.key});

  @override
  State<LoginErrorHistoryDialog> createState() =>
      _LoginErrorHistoryDialogState();
}

class _LoginErrorHistoryDialogState extends State<LoginErrorHistoryDialog> {
  List<LoginErrorRecord> _records = LoginErrorHistory.read();
  bool _clearing = false;

  Future<void> _copy(String report) async {
    try {
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) _message('诊断信息已复制');
    } catch (_) {
      if (mounted) _message('复制失败，请稍后重试');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await LoginErrorHistory.clear();
      if (mounted) setState(() => _records = []);
    } catch (_) {
      if (mounted) _message('清空失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('登录报错历史'),
      content: SizedBox(
        width: 440,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: _records.isEmpty
            ? const Center(child: Text('暂无登录报错记录'))
            : ListView.builder(
                itemCount: _records.length,
                itemBuilder: (context, index) {
                  final record = _records[index];
                  final time = record.time
                      .toLocal()
                      .toString()
                      .split('.')
                      .first;
                  return ExpansionTile(
                    key: ValueKey(record.time.toIso8601String()),
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: index == 0,
                    title: Text(record.result),
                    subtitle: Text(time),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: '复制本条诊断',
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copy(record.report),
                        ),
                      ),
                      SelectableText(
                        record.report,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
      ),
      actions: [
        IconButton(
          tooltip: '清空历史',
          onPressed: _records.isEmpty || _clearing ? null : _clear,
          icon: const Icon(Icons.delete_outline),
        ),
        IconButton(
          tooltip: '复制全部诊断',
          onPressed: _records.isEmpty
              ? null
              : () =>
                    _copy(_records.map((r) => r.report).join('\n\n-----\n\n')),
          icon: const Icon(Icons.copy_all),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
