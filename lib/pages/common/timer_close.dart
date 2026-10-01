import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pilipala/services/shutdown_timer_service.dart';

/// 定时关闭入口按钮：视频/音频模式播放页右上角通用。
///
/// 有生效定时时显示倒计时角标，点击打开设置弹窗。
class TimerCloseButton extends StatelessWidget {
  const TimerCloseButton({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: shutdownTimerService.remaining,
      builder: (context, remaining, _) {
        final bool active = remaining != null;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: active
                  ? '定时关闭（剩余 ${shutdownTimerService.remainingLabel}）'
                  : '定时关闭',
              icon: Icon(
                active ? Icons.timer : Icons.timer_outlined,
                size: 22,
                color: color,
              ),
              onPressed: () => showTimerCloseSheet(context),
            ),
            if (active)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shutdownTimerService.remainingLabel,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 定时关闭设置弹窗：预设时长 + 自定义时/分输入。
Future<void> showTimerCloseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    elevation: 0,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return const _TimerCloseSheet();
    },
  );
}

class _TimerCloseSheet extends StatefulWidget {
  const _TimerCloseSheet();

  @override
  State<_TimerCloseSheet> createState() => _TimerCloseSheetState();
}

class _TimerCloseSheetState extends State<_TimerCloseSheet> {
  static const List<int> presetMinutes = [-1, 15, 30, 60];

  final TextEditingController _hours = TextEditingController();
  final TextEditingController _minutes = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _error;

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _select(int minutes) {
    shutdownTimerService.scheduledExitInMinutes = minutes;
    if (minutes == -1) {
      shutdownTimerService.cancelShutdownTimer();
    } else {
      shutdownTimerService.startShutdownTimer();
    }
    Get.back();
  }

  void _submitCustom() {
    if (!_formKey.currentState!.validate()) return;
    final int h = int.tryParse(_hours.text) ?? 0;
    final int m = int.tryParse(_minutes.text) ?? 0;
    final int total = h * 60 + m;
    if (total < 1) {
      setState(() => _error = '至少需要 1 分钟');
      return;
    }
    shutdownTimerService.startCustomTimer(h, m);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = Theme.of(context).textTheme.titleMedium!;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Center(child: Text('定时关闭', style: titleStyle)),
            const SizedBox(height: 6),
            ValueListenableBuilder<Duration?>(
              valueListenable: shutdownTimerService.remaining,
              builder: (context, remaining, _) {
                if (remaining == null) {
                  return const Center(
                    child: Text('未启用', style: TextStyle(fontSize: 12)),
                  );
                }
                return Center(
                  child: Text(
                    '剩余 ${shutdownTimerService.remainingLabel}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            for (final int choice in presetMinutes) ...<Widget>[
              ListTile(
                onTap: () => _select(choice),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(choice == -1 ? '禁用' : '$choice分钟后'),
                trailing: ValueListenableBuilder<Duration?>(
                  valueListenable: shutdownTimerService.remaining,
                  builder: (context, remaining, _) {
                    // 选中态：当前定时就是该预设（以剩余分钟近似判断启用）
                    final bool selected = choice != -1 &&
                        remaining != null &&
                        shutdownTimerService.scheduledExitInMinutes == choice;
                    final bool disabledSelected =
                        choice == -1 && remaining == null;
                    return (selected || disabledSelected)
                        ? Icon(
                            Icons.done,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : const SizedBox();
                  },
                ),
              ),
            ],
            const SizedBox(height: 6),
            const Center(
              child: SizedBox(width: 100, child: Divider(height: 1)),
            ),
            const SizedBox(height: 10),
            Text('自定义（时 + 分，最少 1 分钟）', style: titleStyle),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hours,
                      decoration: const InputDecoration(labelText: '时'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minutes,
                      decoration: const InputDecoration(labelText: '分'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onFieldSubmitted: (_) => _submitCustom(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _submitCustom,
                    child: const Text('开始'),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            // 结束动作与等待开关（与视频页旧弹窗一致）
            const SizedBox(height: 10),
            StatefulBuilder(
              builder: (context, setStateInner) => ListTile(
                onTap: () {
                  shutdownTimerService.waitForPlayingCompleted =
                      !shutdownTimerService.waitForPlayingCompleted;
                  setStateInner(() {});
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('额外等待视频播放完毕'),
                trailing: Switch(
                  value: shutdownTimerService.waitForPlayingCompleted,
                  onChanged: (value) {
                    shutdownTimerService.waitForPlayingCompleted = value;
                    setStateInner(() {});
                  },
                ),
              ),
            ),
            StatefulBuilder(
              builder: (context, setStateInner) => Row(
                children: [
                  const Text('倒计时结束:'),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      shutdownTimerService.exitApp = false;
                      setStateInner(() {});
                    },
                    child: Text(
                      ' 暂停播放 ',
                      style: TextStyle(
                        fontWeight: !shutdownTimerService.exitApp
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: !shutdownTimerService.exitApp
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      shutdownTimerService.exitApp = true;
                      setStateInner(() {});
                    },
                    child: Text(
                      ' 退出APP ',
                      style: TextStyle(
                        fontWeight: shutdownTimerService.exitApp
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: shutdownTimerService.exitApp
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
