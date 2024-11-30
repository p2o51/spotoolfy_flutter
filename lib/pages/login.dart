import 'package:flutter/material.dart';

class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Welcome(),
          const SizedBox(height: 40),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            onPressed: () {
              // TODO: 实现 Spotify 授权逻辑
            },
            child: const Text('Authorize Spotify'),
          ),
          const SizedBox(height: 16),
          const Text('and',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 64,
            height: 0.9,
          ),
          ),
           const SizedBox(height: 16),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            onPressed: () {
              // TODO: 实现 Google 登录逻辑
            },
            child: const Text('Login with Google'),
          ),
        ],
      ),
    );
  }
}

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text('Kisses',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 96,
            height: 0.9,
          ),
          ),
          Text('for',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 64,
            height: 0.9,
          ),
          ),
          Text('Music.',
          style: TextStyle(
            fontFamily: 'Derivia',
            fontSize: 112,
            height: 0.9,
          ),
          ),
      ],
    );
  }
}