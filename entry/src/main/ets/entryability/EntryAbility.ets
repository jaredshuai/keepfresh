import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ReminderService } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';
import { UsageService } from '../service/UsageService';
import { Theme } from '../common/Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    if (want?.parameters?.filterLevel) {
      const level = want.parameters.filterLevel as string;
      UsageService.getInstance().init(this.context);
      UsageService.getInstance().logNotificationClicked(level);
      AppStorage.setOrCreate('targetFilterLevel', level);
    }
    UsageService.getInstance().init(this.context);
    UsageService.getInstance().logAppOpen();
    SettingsService.getInstance().init(this.context).then(() => {
      return ReminderService.getInstance().syncDailyReminder(this.context);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, `Failed to init settings or sync daily reminder in onCreate: ${err.message}`);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    if (want?.parameters?.filterLevel) {
      const level = want.parameters.filterLevel as string;
      UsageService.getInstance().init(this.context);
      UsageService.getInstance().logNotificationClicked(level);
      AppStorage.setOrCreate('targetFilterLevel', level);
    }
    SettingsService.getInstance().init(this.context).then(() => {
      return ReminderService.getInstance().syncDailyReminder(this.context);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, `Failed to init settings or sync daily reminder in onNewWant: ${err.message}`);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      this.setupImmersiveWindow(windowStage);
    });
  }

  /**
   * 全面屏适配：内容延伸进系统栏区域（沉浸式），状态栏/导航条不再露系统白底。
   * 避让高度写入 AppStorage，各页根容器用 @StorageProp 消费做 padding——
   * 背景色铺满全屏，内容仍留在安全区内，FAB/底部按钮不会沉入手势条。
   */
  private setupImmersiveWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowBackgroundColor(Theme.pageBg);
      const sysArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const ui = mainWindow.getUIContext();
      AppStorage.setOrCreate('avoidTopVp', ui.px2vp(sysArea.topRect.height));
      // 底部两种导航模式互斥：手势条走 NAVIGATION_INDICATOR，三键导航走 TYPE_SYSTEM.bottomRect
      const bottomPx = Math.max(sysArea.bottomRect.height, indicator.bottomRect.height);
      AppStorage.setOrCreate('avoidBottomVp', ui.px2vp(bottomPx));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'immersive window setup failed: %{public}s', JSON.stringify(e) ?? '');
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    SettingsService.getInstance().init(this.context).then(() => {
      return ReminderService.getInstance().syncDailyReminder(this.context);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, `Failed to init settings or sync daily reminder in onForeground: ${err.message}`);
    });
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
