import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05, // 左右各留5%的空间
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.close),
            ),
            const Text(
              'Available Devices',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Consumer<SpotifyProvider>(
              builder: (context, provider, child) {
                final devices = provider.availableDevices;
                final activeDeviceId = provider.activeDeviceId;

                if (devices.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('没有找到可用设备'),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final bool isActive = device['id'] == activeDeviceId;

                    return ListTile(
                      leading: _buildDeviceIcon(device['type']),
                      title: Text(
                        device['name'] ?? '未知设备',
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(_getDeviceTypeName(device['type'])),
                      trailing: isActive 
                        ? Icon(Icons.volume_up, 
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                      onTap: isActive 
                        ? null 
                        : () => _transferPlayback(context, device['id']),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceIcon(String? type) {
    IconData iconData;
    switch (type?.toLowerCase()) {
      case 'computer':
        iconData = Icons.computer;
        break;
      case 'smartphone':
        iconData = Icons.smartphone;
        break;
      case 'speaker':
        iconData = Icons.speaker;
        break;
      default:
        iconData = Icons.devices_other;
    }
    return Icon(iconData);
  }

  String _getDeviceTypeName(String? type) {
    switch (type?.toLowerCase()) {
      case 'computer':
        return '电脑';
      case 'smartphone':
        return '手机';
      case 'speaker':
        return '音箱';
      default:
        return '其他设备';
    }
  }

  Future<void> _transferPlayback(BuildContext context, String deviceId) async {
    try {
      final provider = Provider.of<SpotifyProvider>(context, listen: false);
      await provider.transferPlaybackToDevice(deviceId, play: true);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已切换播放设备')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换设备失败: $e')),
        );
      }
    }
  }
}