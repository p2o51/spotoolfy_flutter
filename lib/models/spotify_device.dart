enum SpotifyDeviceType {
  computer,
  smartphone,
  speaker,
  unknown;

  factory SpotifyDeviceType.fromString(String? type) {
    switch (type?.toLowerCase()) {
      case 'computer':
        return SpotifyDeviceType.computer;
      case 'smartphone':
        return SpotifyDeviceType.smartphone;
      case 'speaker':
        return SpotifyDeviceType.speaker;
      default:
        return SpotifyDeviceType.unknown;
    }
  }
}

class SpotifyDevice {
  final String? id;
  final String name;
  final SpotifyDeviceType type;
  final bool isActive;
  final bool isPrivateSession;
  final bool isRestricted;
  final int? volumePercent;
  final bool supportsVolume;

  SpotifyDevice({
    this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.isPrivateSession,
    required this.isRestricted,
    this.volumePercent,
    required this.supportsVolume,
  });

  factory SpotifyDevice.fromJson(Map<String, dynamic> json) {
    return SpotifyDevice(
      id: json['id'],
      name: json['name'] ?? 'Unknown Device',
      type: SpotifyDeviceType.fromString(json['type']),
      isActive: json['is_active'] ?? false,
      isPrivateSession: json['is_private_session'] ?? false,
      isRestricted: json['is_restricted'] ?? false,
      volumePercent: json['volume_percent'],
      supportsVolume: json['supports_volume'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString().split('.').last,
      'is_active': isActive,
      'is_private_session': isPrivateSession,
      'is_restricted': isRestricted,
      'volume_percent': volumePercent,
      'supports_volume': supportsVolume,
    };
  }
} 