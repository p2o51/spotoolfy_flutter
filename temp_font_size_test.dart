import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FontSizeTest(),
    );
  }
}

class FontSizeTest extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 获取 bodyLarge 的字体大小
    final bodyLargeSize = theme.textTheme.bodyLarge?.fontSize;
    
    print('bodyLarge fontSize: $bodyLargeSize');
    
    return Scaffold(
      appBar: AppBar(title: Text('Font Size Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'bodyLarge 字体大小: ${bodyLargeSize ?? "默认"}',
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: 20),
            Text(
              '这是 bodyLarge 样式的文本',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
