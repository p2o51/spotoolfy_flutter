import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../models/spotify_device.dart';
import '../widgets/materialui.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  'Devices',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Consumer<SpotifyProvider>(
            builder: (context, spotify, child) {
              final devices = spotify.availableDevices;
              
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
                  return DeviceListItem(
                    device: device,
                    isFirst: index == 0,
                    isLast: index == devices.length - 1,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class DeviceListItem extends StatelessWidget {
  final SpotifyDevice device;
  final bool isFirst;
  final bool isLast;

  const DeviceListItem({
    super.key,
    required this.device,
    this.isFirst = false,
    this.isLast = false,
  });

  IconData _getDeviceIcon() {
    switch (device.type) {
      case SpotifyDeviceType.computer:
        return Icons.computer_rounded;
      case SpotifyDeviceType.smartphone:
        return Icons.smartphone_rounded;
      case SpotifyDeviceType.speaker:
        return Icons.speaker_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  bool _isSonosDevice(String name) {
    return name.toLowerCase().contains('sonos');
  }

  String? _getDeviceRestriction(BuildContext context) {
    if (_isSonosDevice(device.name)) {
      return '请使用 Spotify 或 Sonos 应用控制此设备';
    }
    if (device.isRestricted) {
      return '此设备不可用';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spotify = Provider.of<SpotifyProvider>(context, listen: false);
    final isActive = device.isActive;
    final restriction = _getDeviceRestriction(context);
    final isSonos = _isSonosDevice(device.name);
    final isDisabled = device.isRestricted || isSonos;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isFirst ? 24 : 8),
          topRight: Radius.circular(isFirst ? 24 : 8),
          bottomLeft: Radius.circular(isLast ? 24 : 8),
          bottomRight: Radius.circular(isLast ? 24 : 8),
        ),
      ),
      color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6),
      child: InkWell(
        onTap: isDisabled ? null : () {
          spotify.transferPlaybackToDevice(device.id!, play: true);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    _getDeviceIcon(),
                    size: 32,
                    color: isDisabled
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isDisabled
                              ? Theme.of(context).colorScheme.outline
                              : null,
                          ),
                        ),
                        if (restriction != null)
                          Text(
                            restriction,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isSonos 
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.error,
                            ),
                          )
                        else if (device.isPrivateSession)
                          Text(
                            'Private Session',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Current',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}