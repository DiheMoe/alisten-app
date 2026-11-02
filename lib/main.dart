import 'dart:async';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/assembly.dart';
import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/third_party_http.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/playback/data/alisten_audio_handler.dart';
import 'package:alisten/features/playback/data/unavailable_audio_engine.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main({
  Future<AudioEngine> Function() startAudio = _startAudio,
  AlistenApi? api,
  CredentialStore Function(String serverId)? credentialStores,
  Stream<List<ConnectivityResult>>? connectivityStatus,
  AppLinkSource? appLinks,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  final preferences = await SharedPreferences.getInstance();
  final environment = BuildEnvironment.fromEnvironment();
  // 必须在读取存储之前完成迁移，否则已有的成员和最近房间会被当作不存在。
  await migrateStorage(preferences, environment: environment);
  await sweepServerData(preferences, environment: environment);
  final engine = await _audioEngine(startAudio);
  runApp(
    ProviderScope(
      overrides: [
        ...alistenWiring(preferences, environment: environment),
        ...platformAdapters(
          audioEngine: engine,
          api: api,
          credentialStores: credentialStores,
          connectivityStatus: connectivityStatus,
          appLinks: appLinks,
        ),
      ],
      child: const AlistenApp(),
    ),
  );
}

// 异常消息可能带有设备或地址信息，只记录类型。
Future<AudioEngine> _audioEngine(Future<AudioEngine> Function() start) async {
  try {
    return await start();
  } on Object catch (error) {
    AppLog.error(
      'audio',
      'audio service not started',
      type: '${error.runtimeType}',
    );
    return const UnavailableAudioEngine();
  }
}

Future<AudioEngine> _startAudio() async {
  final handler = await AlistenAudioHandler.create(newThirdPartyDio());
  await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'moe.dihe.alisten.audio',
      androidNotificationChannelName: 'Alisten 播放',
      androidNotificationIcon: 'drawable/ic_stat_alisten',
      // Android 12 起不允许从后台再次启动前台服务，暂停和切歌间隙也要留在前台。
      androidStopForegroundOnPause: false,
    ),
  );
  return RoomAudioEngine(handler);
}
