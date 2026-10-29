import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:tronclass/auth/auth_controller.dart';
import 'package:tronclass/auth/login_dialogs.dart';
import 'package:tronclass/auth/saved_account_storage.dart';
import 'package:tronclass/common/toast.dart';
import 'package:tronclass/data/changke_client.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/data/service/login.dart';

class LoginController extends GetxController {
  LoginController({this.initialUsername, this.initialPassword});

  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final isSubmitting = false.obs;
  final passwordVisible = false.obs;
  final passwordErrorCount = 0.obs;
  final suppressPasswordError = true.obs;
  final isFirstLoginAttempt = true.obs;

  final String? initialUsername;
  final String? initialPassword;
  Route<dynamic>? _loginRoute;

  bool get _isCurrentPage => !isClosed && _loginRoute?.isCurrent == true;

  @override
  void onInit() {
    super.onInit();
    final savedUsername =
        initialUsername ??
        getStorage.read<String>(GetStorageKeys.lastLoginUsername);
    if (savedUsername?.isNotEmpty ?? false) {
      usernameController.text = savedUsername!;
      ChangkeClient.getInstance(username: savedUsername);
    }
    if (initialPassword?.isNotEmpty ?? false) {
      passwordController.text = initialPassword!;
    }
  }

  Future<void> submit() async {
    if (isClosed || isSubmitting.value) return;
    final context = formKey.currentContext;
    if (context == null ||
        !context.mounted ||
        !(formKey.currentState?.validate() ?? false)) {
      return;
    }
    _loginRoute = ModalRoute.of(context);
    if (!_isCurrentPage) return;

    isSubmitting.value = true;
    final username = usernameController.text.trim();
    final password = passwordController.text;
    final client = ChangkeClient.getInstance(username: username);
    final attemptLimit = isFirstLoginAttempt.value ? 3 : 1;
    isFirstLoginAttempt.value = false;

    try {
      Object? lastError;
      var authenticated = false;
      for (var attempt = 0; attempt < attemptLimit; attempt++) {
        if (!_isCurrentPage) return;
        try {
          await _authenticate(client, username: username, password: password);
          authenticated = true;
          break;
        } on LoginCancelledException {
          return;
        } catch (error) {
          lastError = error;
        }
      }

      if (!_isCurrentPage) return;
      if (!authenticated) {
        if (lastError != null) _handleLoginError(lastError);
        return;
      }

      // UI and persistence errors must not trigger another password submission.
      await SavedAccountStorage.upsertAccount(
        username: username,
        password: password,
      );
      await getStorage.write(GetStorageKeys.lastLoginUsername, username);
      await getStorage.write(GetStorageKeys.isCleanWebSession, true);
      if (!_isCurrentPage || !context.mounted) return;
      if (Get.isRegistered<AuthController>()) {
        Get.find<AuthController>().refreshState();
      }
      passwordErrorCount.value = 0;
      suppressPasswordError.value = true;
      FocusScope.of(context).unfocus();
      toastSuccess0('登录成功');
      Get.back(result: true);
    } catch (error) {
      if (_isCurrentPage) _handleLoginError(error);
    } finally {
      if (!isClosed) isSubmitting.value = false;
    }
  }

  Future<void> _authenticate(
    ChangkeClient client, {
    required String username,
    required String password,
  }) async {
    Future<void> login() => client.login(
      username: username,
      password: password,
      captchaRequester: _showCaptchaDialog,
    );
    try {
      await login();
    } on RequireLoginVerificationCodeException {
      if (!_isCurrentPage) throw const LoginCancelledException();
      final verified = await _showVerificationCodeDialog(
        casDio: client.casDio,
        username: username,
      );
      if (!verified || !_isCurrentPage) throw const LoginCancelledException();
      await login();
    }
  }

  void togglePasswordVisibility() {
    if (!isClosed) passwordVisible.value = !passwordVisible.value;
  }

  Future<String> _showCaptchaDialog(Uint8List image) async {
    if (!_isCurrentPage) throw const LoginCancelledException();
    final result = await Get.dialog<String>(
      LoginCaptchaDialog(image: image),
      barrierDismissible: false,
    );
    if (result == null || !_isCurrentPage) {
      throw const LoginCancelledException();
    }
    return result;
  }

  Future<bool> _showVerificationCodeDialog({
    required Dio casDio,
    required String username,
  }) async {
    return await Get.dialog<bool>(
          LoginVerificationDialog(
            sendCode: () =>
                LoginService.sendDynamicCode(dio: casDio, username: username),
            verifyCode: (code) =>
                LoginService.reAuthCheck(dio: casDio, code: code),
          ),
          barrierDismissible: false,
        ) ??
        false;
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  void _handleLoginError(Object error) {
    if (!_isCurrentPage) return;
    final message = error.toString();
    final isPasswordError =
        message.contains('密码有误') || message.contains('密码错误');
    if (isPasswordError) {
      passwordErrorCount.value++;
      if (suppressPasswordError.value && passwordErrorCount.value <= 3) {
        toastFailure0('登录过程发生错误，请核对密码并重试');
      } else {
        suppressPasswordError.value = false;
        toastFailure0('登录失败，请检查密码并重试');
      }
      return;
    }
    toastFailure(message: '登录失败', error: error);
  }
}
