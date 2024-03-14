import 'dart:async';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../daos/bot_instance_dao.dart';
import '../services/config_service.dart';
import '../utils/logger.dart';
import '../models/bot_instance.dart';
import '../utils/util.dart';
/// BotInstanceService
/// 
/// 用於管理BotInstance(Service)
/// 
/// * 方法:
/// 1. getBotInstance: 從LocalStorage取得BotInstance清單
/// 2. saveBotInstance: 儲存BotInstance清單到LocalStorage
/// 3. saveBotInstanceByUuid: 覆蓋指定uuid的BotInstance
/// 4. openBotInstance: 開啟BotInstance
/// 5. closeBotInstance: 關閉BotInstance
/// 6. deleteBotInstance: 刪除BotInstance
/// 7. openBotInstanceFolder: 開啟BotInstance資料夾
class BotInstanceService{

  /// 從LocalStorage取得BotInstance清單
  static Future<List<BotInstance>> getBotInstance() async {
    logger.i("進入getBotInstance");
    return await BotInstanceDaoLocalStorage.getBotInstance();
  }

  /// 儲存BotInstance清單到LocalStorage
  static Future<void> saveBotInstance(List<BotInstance> instances) async {
    logger.i("進入saveBotInstance");
    await BotInstanceDaoLocalStorage.saveBotInstance(instances);
  }

  /// 覆蓋指定uuid的BotInstance
  static Future<void> saveBotInstanceByUuid(String uuid,BotInstance instance) async {
    logger.i("進入saveBotInstanceByUuid");
    await BotInstanceDaoLocalStorage.saveBotInstanceByUuid(uuid,instance);
  }

  /// 開啟BotInstance
  static Future<void> openBotInstance(BotInstance instance,{int? expressPort, int? websocketPort}) async {
    logger.i("進入openBotInstance");
    final env = await ConfigService.getEnv(instance.uuid);
    expressPort ??= await Util.getAvailablePort(int.parse(dotenv.env['EXPRESS_PORT']!));
    logger.d("expressPort: $expressPort");
    ConfigService.modifyEnv(env, 'EXPRESS_PORT', expressPort);
    websocketPort ??= await Util.getAvailablePort(int.parse(dotenv.env['WEBSOCKET_PORT']!));
    logger.d("websocketPort: $websocketPort");
    ConfigService.modifyEnv(env, 'WEBSOCKET_PORT', websocketPort);
    await ConfigService.saveEnv(env, instance.uuid);
    final baseDir = await getApplicationCacheDirectory();
    final executablePath = join(baseDir.path,"instance",instance.uuid,"${instance.type.value.toLowerCase()}.exe");
    logger.d("開始執行$executablePath");
    
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.start("chmod", ["+x", executablePath]);
    }
    final process = await Process.start(executablePath, [], workingDirectory: join(baseDir.path,"instance",instance.uuid));
    
    instance.isProcess = true;
    instance.process = process;
    instance.expressPort = expressPort;
    instance.websocketPort = websocketPort;
    // 轉為廣播Stream，讓多個監聽器可以監聽 參考資料: https://blog.csdn.net/adojayfan/article/details/121251801
    instance.stderrStream = process.stderr.asBroadcastStream(); 
    instance.stdoutStream = process.stdout.asBroadcastStream(); 
    
    //執行時間的計時器
    instance.timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      instance.duration++;
    });

    logger.d(process.pid);
  }

  /// 關閉BotInstance
  static void closeBotInstance(BotInstance instance) async {
    logger.i("進入closeBotInstance");
    instance.process!.kill();
    instance.isProcess = false;
    instance.process = null;
    instance.expressPort = null;
    instance.websocketPort = null;
    instance.stderrStream = null;
    instance.stdoutStream = null;
    instance.timer!.cancel();
    instance.duration = 0;
  }

  /// 刪除BotInstance
  static void deleteBotInstance(BotInstance instance) async {
    logger.i("進入deleteBotInstance，刪除BotInstance");
    final baseDir = await getApplicationCacheDirectory();
    final instanceDir = Directory(join(baseDir.path,"instance",instance.uuid));
    await instanceDir.delete(recursive: true);
  }
  
  /// 開啟BotInstance資料夾
  static openBotInstanceFolder(BotInstance instance) async {
    logger.i("進入openBotInstanceFolder，開啟BotInstance資料夾");
    final baseDir = await getApplicationCacheDirectory();
    final instanceDir = Directory(join(baseDir.path,"instance",instance.uuid));
    Util.openFileManager(instanceDir);
  }

  static Future<BotInstance> copyBotInstance(BotInstance instance) async {
    // 複製資料夾(內部函數)
    Future<void> copyDirectory(Directory source, Directory destination) async {
      await for (var entity in source.list(recursive: false)) {
        if (entity is Directory) {
          var newDirectory = Directory(join(destination.absolute.path, basename(entity.path)));
          await newDirectory.create();
          await copyDirectory(entity.absolute, newDirectory);
        } else if (entity is File) {
          await entity.copy(join(destination.path, basename(entity.path)));
        }
      }
    }
    logger.i("進入copyBotInstance，複製BotInstance");
    final baseDir = await getApplicationCacheDirectory();
    final instanceDir = Directory(join(baseDir.path,"instance",instance.uuid));
    // 產生新的uuid
    const uuidInstance = Uuid(); 
    final uuid = uuidInstance.v4();
    // 複製BotInstance
    final copyInstance = instance.copyWith(uuid: uuid);
    final copyInstanceDir = Directory(join(baseDir.path,"instance",uuid));
    //新增資料夾
    await copyInstanceDir.create(recursive: true);
    await copyDirectory(instanceDir, copyInstanceDir);
    return copyInstance;
  }
}