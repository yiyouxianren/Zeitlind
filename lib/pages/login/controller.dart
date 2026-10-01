import 'dart:async';

import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/login.dart';
import 'package:gt3_flutter_plugin/gt3_flutter_plugin.dart';
import 'package:pilipala/models/login/index.dart';
import 'package:pilipala/utils/login.dart';

class LoginPageController extends GetxController {
  final GlobalKey mobFormKey = GlobalKey<FormState>();
  final GlobalKey passwordFormKey = GlobalKey<FormState>();
  final GlobalKey msgCodeFormKey = GlobalKey<FormState>();

  final TextEditingController mobTextController = TextEditingController();
  final TextEditingController passwordTextController = TextEditingController();
  final TextEditingController msgCodeTextController = TextEditingController();

  final FocusNode mobTextFieldNode = FocusNode();
  final FocusNode passwordTextFieldNode = FocusNode();
  final FocusNode msgCodeTextFieldNode = FocusNode();

  final PageController pageViewController = PageController();

  RxInt currentIndex = 0.obs;

  final Gt3FlutterPlugin captcha = Gt3FlutterPlugin();

  // 倒计时60s
  RxInt seconds = 60.obs;
  Timer? timer;
  RxBool smsCodeSendStatus = false.obs;

  // 默认密码登录
  RxInt loginType = 0.obs;

  String? captchaKey;

  String tel = '';
  String webSmsCode = '';
  bool _captchaLoading = false;
  bool _qrPolling = false;

  RxInt validSeconds = 180.obs;
  Timer? validTimer;
  String qrcodeKey = '';
  RxBool passwordVisible = false.obs;

  // 监听pageView切换
  void onPageChange(int index) {
    currentIndex.value = index;
  }

  // 输入手机号 下一页
  void nextStep() async {
    if ((mobFormKey.currentState as FormState).validate()) {
      await pageViewController.animateToPage(
        1,
        duration: const Duration(microseconds: 3000),
        curve: Curves.easeInOut,
      );
      passwordTextFieldNode.requestFocus();
      (mobFormKey.currentState as FormState).save();
    }
  }

  // 上一页
  void previousPage() async {
    passwordTextFieldNode.unfocus();
    await Future.delayed(const Duration(milliseconds: 200));
    pageViewController.animateToPage(
      0,
      duration: const Duration(microseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 切换登录方式
  void changeLoginType() {
    loginType.value = loginType.value == 0 ? 1 : 0;
    if (loginType.value == 0) {
      passwordTextFieldNode.requestFocus();
    } else {
      msgCodeTextFieldNode.requestFocus();
    }
  }

  // app端密码登录
  Future<void> loginInByAppPassword() async {
    if (tel.isEmpty) tel = mobTextController.text.trim();
    if (tel.isEmpty) {
      SmartDialog.showToast('请输入手机号');
      return;
    }
    if (!(passwordFormKey.currentState as FormState).validate()) return;
    try {
      final webKeyRes = await LoginHttp.getWebKey();
      if (webKeyRes['status'] != true) {
        SmartDialog.showToast(webKeyRes['msg'] ?? '获取登录密钥失败');
        return;
      }
      final res = await LoginHttp.loginInByMobPwd(
        tel: tel,
        password: passwordTextController.text,
        key: webKeyRes['data']['key'],
        rhash: webKeyRes['data']['hash'],
      );
      if (res['status'] == true) {
        await LoginUtils.confirmLogin('', null);
      } else {
        SmartDialog.showToast(res['msg'] ?? '密码登录失败');
      }
    } catch (_) {
      SmartDialog.showToast('登录请求失败，请稍后重试');
    }
  }

  // web端密码登录
  Future<void> loginInByWebPassword() async {
    if (tel.isEmpty) tel = mobTextController.text.trim();
    if (tel.isEmpty) {
      SmartDialog.showToast('请输入手机号');
      return;
    }
    if (!(passwordFormKey.currentState as FormState).validate()) return;
    await getCaptcha((CaptchaDataModel captchaData) async {
      final webKeyRes = await LoginHttp.getWebKey();
      if (webKeyRes['status'] != true) {
        SmartDialog.showToast(webKeyRes['msg'] ?? '获取登录密钥失败');
        return;
      }
      final key = webKeyRes['data']['key'];
      final hash = webKeyRes['data']['hash'];
      final encrypted = Encrypter(RSA(publicKey: RSAKeyParser().parse(key) as RSAPublicKey))
          .encrypt(hash + passwordTextController.text)
          .base64;
      final geetest = captchaData.geetest;
      if (geetest == null) {
        SmartDialog.showToast('验证服务返回数据不完整');
        return;
      }
      if (captchaData.token == null || geetest?.challenge == null ||
          captchaData.validate == null || captchaData.seccode == null) {
        SmartDialog.showToast('安全验证信息不完整，请重试');
        return;
      }
      final res = await LoginHttp.loginInByWebPwd(
        username: tel,
        password: encrypted,
        token: captchaData.token!,
        challenge: geetest!.challenge!,
        validate: captchaData.validate!,
        seccode: captchaData.seccode!,
      );
      if (res['status'] == true) {
        await LoginUtils.confirmLogin('', null);
      } else if (res['url'] is String && (res['url'] as String).isNotEmpty) {
        Get.toNamed('/webview', parameters: {
          'url': res['url'],
          'type': 'url',
          'pageTitle': '登录验证',
        });
      } else {
        SmartDialog.showToast(res['msg'] ?? '密码登录失败');
      }
    });
  }

  // web端验证码登录
  Future<void> loginInByCode() async {
    final form = msgCodeFormKey.currentState as FormState;
    if (!form.validate()) return;
    form.save();
    final key = captchaKey;
    if (key == null || key.isEmpty) {
      SmartDialog.showToast('请先获取短信验证码');
      return;
    }
    final res = await LoginHttp.loginInByWebSmsCode(
      cid: 86,
      tel: tel,
      code: webSmsCode,
      captchaKey: key,
    );
    if (res['status'] == true) {
      await LoginUtils.confirmLogin('', null);
    } else {
      SmartDialog.showToast(res['msg'] ?? '验证码登录失败');
    }
  }

  // 获取app端验证码
  Future<void> getAppMsgCode() async {
    await getCaptcha((CaptchaDataModel captchaData) async {
      final geetest = captchaData.geetest;
      if (geetest == null) {
        SmartDialog.showToast('验证服务返回数据不完整');
        return;
      }
      if (captchaData.token == null || geetest?.challenge == null ||
          captchaData.validate == null || captchaData.seccode == null) {
        SmartDialog.showToast('安全验证信息不完整，请重试');
        return;
      }
      final res = await LoginHttp.sendAppSmsCode(
        cid: 86,
        tel: tel,
        token: captchaData.token!,
        challenge: geetest!.challenge!,
        validate: captchaData.validate!,
        seccode: captchaData.seccode!,
      );
      SmartDialog.showToast(res['status'] == true ? '验证码已发送' : (res['msg'] ?? '验证码发送失败'));
    });
  }

  // 申请极验验证码
  Future<void> getCaptcha(Future<void> Function(CaptchaDataModel) oncall) async {
    if (_captchaLoading) return;
    _captchaLoading = true;
    SmartDialog.showLoading(msg: '请求中...');
    try {
      final result = await LoginHttp.queryCaptcha();
      if (result['status'] != true) {
        SmartDialog.showToast(result['msg'] ?? '获取验证失败');
        return;
      }
      final captchaData = result['data'] as CaptchaDataModel;
      final geetest = captchaData.geetest;
      if (geetest == null) {
        SmartDialog.showToast('验证服务返回数据不完整');
        return;
      }
      if (geetest?.challenge == null || geetest?.gt == null) {
        SmartDialog.showToast('验证服务返回数据不完整');
        return;
      }
      captcha.addEventHandler(
        onShow: (_) async => SmartDialog.dismiss(),
        onClose: (_) async => SmartDialog.showToast('取消验证'),
        onResult: (message) async {
          if (message['code']?.toString() != '1') {
            SmartDialog.showToast('安全验证未通过');
            return;
          }
          final data = message['result'];
          if (data is! Map) {
            SmartDialog.showToast('安全验证返回数据异常');
            return;
          }
          captchaData.validate = data['geetest_validate']?.toString();
          captchaData.seccode = data['geetest_seccode']?.toString();
          geetest.challenge = data['geetest_challenge']?.toString();
          await oncall(captchaData);
        },
        onError: (_) async => SmartDialog.showToast('安全验证失败，请重试'),
      );
      captcha.startCaptcha(Gt3RegisterData(
        challenge: geetest.challenge,
        gt: geetest.gt!,
        success: true,
      ));
    } catch (_) {
      SmartDialog.showToast('获取验证失败，请稍后重试');
    } finally {
      _captchaLoading = false;
      SmartDialog.dismiss();
    }
  }

  // 获取web端验证码
  Future<void> getWebMsgCode() async {
    if (smsCodeSendStatus.value) return;
    await getCaptcha((CaptchaDataModel captchaData) async {
      final geetest = captchaData.geetest;
      if (geetest == null) {
        SmartDialog.showToast('验证服务返回数据不完整');
        return;
      }
      if (captchaData.token == null || geetest?.challenge == null ||
          captchaData.validate == null || captchaData.seccode == null) {
        SmartDialog.showToast('安全验证信息不完整，请重试');
        return;
      }
      final res = await LoginHttp.sendWebSmsCode(
        cid: 86,
        tel: tel,
        token: captchaData.token!,
        challenge: geetest!.challenge!,
        validate: captchaData.validate!,
        seccode: captchaData.seccode!,
      );
      if (res['status'] == true && res['data']['captcha_key'] is String) {
        captchaKey = res['data']['captcha_key'];
        SmartDialog.showToast('验证码已发送');
        startTimer();
      } else {
        SmartDialog.showToast(res['msg'] ?? '验证码发送失败');
      }
    });
  }

  // 验证码倒计时
  void startTimer() {
    timer?.cancel();
    seconds.value = 60;
    smsCodeSendStatus.value = true;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (seconds.value > 0) {
        seconds.value--;
      } else {
        timer.cancel();
        smsCodeSendStatus.value = false;
      }
    });
  }

  Future<Map<String, dynamic>?> getWebQrcode() async {
    validTimer?.cancel();
    final res = await LoginHttp.getWebQrcode();
    validSeconds.value = 180;
    if (res['status'] == true && res['data']['qrcode_key'] is String) {
      qrcodeKey = res['data']['qrcode_key'];
      validTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (validSeconds.value <= 0) {
          validTimer?.cancel();
          return;
        }
        validSeconds.value--;
        await queryWebQrcodeStatus();
      });
      return res;
    }
    SmartDialog.showToast(res['msg'] ?? '获取二维码失败');
    return null;
  }

  Future<void> queryWebQrcodeStatus() async {
    if (_qrPolling || !hasQrcodeKey) return;
    _qrPolling = true;
    try {
      final res = await LoginHttp.queryWebQrcodeStatus(qrcodeKey);
      if (res['status'] == true) {
        validTimer?.cancel();
        await LoginUtils.confirmLogin('', null);
        if (Get.isDialogOpen == true) Get.back();
      } else if (res['state'] == 'expired') {
        validTimer?.cancel();
        SmartDialog.showToast(res['msg'] ?? '二维码已过期，请刷新');
      }
    } finally {
      _qrPolling = false;
    }
  }

  bool get hasQrcodeKey => qrcodeKey.isNotEmpty;

  @override
  void onClose() {
    timer?.cancel();
    validTimer?.cancel();
    mobTextController.dispose();
    passwordTextController.dispose();
    msgCodeTextController.dispose();
    mobTextFieldNode.dispose();
    passwordTextFieldNode.dispose();
    msgCodeTextFieldNode.dispose();
    pageViewController.dispose();
    super.onClose();
  }}
