import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AudioTimeJumpDialog extends StatefulWidget {
  const AudioTimeJumpDialog({
    super.key,
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;

  @override
  State<AudioTimeJumpDialog> createState() => _AudioTimeJumpDialogState();
}

class _AudioTimeJumpDialogState extends State<AudioTimeJumpDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hours = TextEditingController(text: '${widget.position.inHours}');
    _minutes = TextEditingController(text: '${widget.position.inMinutes % 60}');
    _seconds = TextEditingController(text: '${widget.position.inSeconds % 60}');
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final target = Duration(
      hours: int.parse(_hours.text),
      minutes: int.parse(_minutes.text),
      seconds: int.parse(_seconds.text),
    );
    if (target > widget.duration) {
      setState(() => _error = '跳转时间不能超过音频总时长');
      return;
    }
    Navigator.of(context).pop(target);
  }

  Widget _field(String label, TextEditingController controller, int max) {
    return Expanded(
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        validator: (text) {
          final value = int.tryParse(text ?? '');
          if (value == null) return '请输入数字';
          if (value > max) return '最多 $max';
          return null;
        },
        onFieldSubmitted: (_) => _submit(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('时间跳转'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('输入要跳转到的位置（时 / 分 / 秒）'),
              const SizedBox(height: 12),
              Row(children: [
                _field('时', _hours, 999999),
                const SizedBox(width: 12),
                _field('分', _minutes, 59),
                const SizedBox(width: 12),
                _field('秒', _seconds, 59),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('跳转')),
      ],
    );
  }
}
