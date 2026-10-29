import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tronclass/data/service/login.dart';

class LoginCaptchaDialog extends StatefulWidget {
  const LoginCaptchaDialog({super.key, required this.image});

  final Uint8List image;

  @override
  State<LoginCaptchaDialog> createState() => _LoginCaptchaDialogState();
}

class _LoginCaptchaDialogState extends State<LoginCaptchaDialog> {
  final _controller = TextEditingController();
  bool _closing = false;

  void _finish(String? value) {
    if (_closing) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('请输入验证码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(
              widget.image,
              width: 160,
              height: 80,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(hintText: '验证码'),
              onSubmitted: (_) => _finish(_controller.text.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _finish(null), child: const Text('取消')),
        FilledButton(
          onPressed: () => _finish(_controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class LoginVerificationDialog extends StatefulWidget {
  const LoginVerificationDialog({
    super.key,
    required this.sendCode,
    required this.verifyCode,
  });

  final Future<DynamicCodeResponse> Function() sendCode;
  final Future<ReAuthResponse> Function(String code) verifyCode;

  @override
  State<LoginVerificationDialog> createState() =>
      _LoginVerificationDialogState();
}

class _LoginVerificationDialogState extends State<LoginVerificationDialog> {
  final _controller = TextEditingController();
  Timer? _timer;
  int? _countdown;
  String? _maskedMobile;
  String? _message;
  bool _sending = false;
  bool _verifying = false;
  bool _closing = false;

  bool get _active => mounted && !_closing;

  void _finish(bool result) {
    if (!_active) return;
    _closing = true;
    _timer?.cancel();
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(result);
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _countdown = seconds > 0 ? seconds : null;
    if (_countdown == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_active) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdown! > 1) {
          _countdown = _countdown! - 1;
        } else {
          _countdown = null;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    if (!_active || _sending || _countdown != null) return;
    setState(() => _sending = true);
    try {
      final response = await widget.sendCode();
      if (!_active) return;
      setState(() {
        _maskedMobile = response.mobile;
        _message = response.returnMessage ?? '验证码已发送';
        _startCountdown(response.codeTime ?? 120);
      });
    } catch (_) {
      if (_active) setState(() => _message = '发送验证码失败，请稍后重试');
    } finally {
      if (_active) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!_active || _verifying) return;
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _message = '请输入短信验证码');
      return;
    }
    setState(() => _verifying = true);
    try {
      final response = await widget.verifyCode(code);
      if (!_active) return;
      if (response.code == 'reAuth_success') {
        _finish(true);
      } else {
        setState(() => _message = response.msg ?? '验证失败，请重试');
      }
    } catch (_) {
      if (_active) setState(() => _message = '验证失败，请稍后重试');
    } finally {
      if (_active) setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closing = true;
          _timer?.cancel();
        }
      },
      child: AlertDialog(
        title: const Text('短信验证'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('智慧校园要求短信二次验证，请先发送验证码并输入完成验证。'),
              if (_maskedMobile != null) ...[
                const SizedBox(height: 8),
                Text('验证码已发送到：$_maskedMobile'),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _verifyCode(),
                decoration: InputDecoration(
                  labelText: '短信验证码',
                  hintText: '请输入短信验证码',
                  prefixIcon: const Icon(Icons.message),
                  suffixIcon: _countdown == null
                      ? IconButton(
                          tooltip: '发送验证码',
                          onPressed: _sending ? null : _sendCode,
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        )
                      : SizedBox(
                          width: 56,
                          child: Center(child: Text('${_countdown!}s')),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _verifying ? null : () => _finish(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _verifying ? null : _verifyCode,
            child: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('验证并继续'),
          ),
        ],
      ),
    );
  }
}
