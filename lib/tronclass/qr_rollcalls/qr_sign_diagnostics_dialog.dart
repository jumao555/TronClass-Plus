import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QrSignDiagnosticsDialog extends StatelessWidget {
  const QrSignDiagnosticsDialog({super.key, required this.report});

  final String report;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('扫码错误详情'),
      content: SizedBox(
        width: 380,
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: SingleChildScrollView(
          child: SelectableText(report, style: const TextStyle(fontSize: 13)),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('复制诊断信息'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
