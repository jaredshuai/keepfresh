import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ReminderService } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    if (want?.parameters?.filterLevel) {
      AppStorage.setOrCreate('targetFilterLevel', want.parameters.filterLevel as string);
    }
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
      AppStorage.setOrCreate('targetFilterLevel', want.parameters.filterLevel as string);
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
    });
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
