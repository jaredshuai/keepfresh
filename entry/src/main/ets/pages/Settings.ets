/**
 * 设置中心页 —— 鸿蒙官方设计风格。
 * 包含：临期提醒阈值配置、每日提醒时间/开关、数据备份入口、自定义字段管理入口、关于。
 */
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';

const CLR_BRAND = '#2FA84F';
const CLR_BG = '#F1F3F5';
const CLR_CARD = '#FFFFFF';
const CLR_TEXT = '#182431';
const CLR_TEXT_SUB = '#99182431';
const CLR_TEXT_TIP = '#4D182431';
const CLR_INPUT_BG = '#F1F3F5';
const CLR_DANGER = '#FA2A2D';
const CLR_BORDER = '#E5E5E5';

const PRESET_THRESHOLDS: number[] = [3, 7, 14, 30];

@Entry
@Component
struct Settings {
  @State nearExpiryDaysStr: string = '7';
  @State nearExpiryError: string = '';
  @State reminderEnabled: boolean = true;
  @State reminderHour: number = 8;
  @State reminderMinute: number = 0;
  private settingsService: SettingsService = SettingsService.getInstance();
  private reminderService: ReminderService = ReminderService.getInstance();

  onPageShow(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadAllSettings(ctx);
  }

  private async loadAllSettings(ctx: common.UIAbilityContext): Promise<void> {
    try {
      await this.settingsService.init(ctx);
      const days = await this.settingsService.getNearExpiryDays();
      this.nearExpiryDaysStr = days.toString();

      const reminderSettings: ReminderSettings = await this.reminderService.getSettings();
      this.reminderEnabled = reminderSettings.enabled;
      this.reminderHour = reminderSettings.hour;
      this.reminderMinute = reminderSettings.minute;
    } catch (e) {
      console.error(`load settings failed: ${(e as BusinessError).message}`);
    }
  }

  private async handleThresholdChange(valueStr: string): Promise<void> {
    this.nearExpiryDaysStr = valueStr;
    const err = this.settingsService.validateNearExpiryDays(valueStr);
    if (err) {
      this.nearExpiryError = err;
      return;
    }
    this.nearExpiryError = '';
    const days = parseInt(valueStr, 10);
    const ok = await this.settingsService.updateNearExpiryDays(days);
    if (ok) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.reminderService.syncDailyReminder(ctx);
      promptAction.showToast({ message: `已设置临期阈值为 ${days} 天` });
    }
  }

  private formatTime(hour: number, minute: number): string {
    const h = hour < 10 ? `0${hour}` : `${hour}`;
    const m = minute < 10 ? `0${minute}` : `${minute}`;
    return `${h}:${m}`;
  }

  private pickReminderTime(): void {
    const selectedDate = new Date();
    selectedDate.setHours(this.reminderHour, this.reminderMinute, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selectedDate,
      useMilitaryTime: true,
      onAccept: async (value: TimePickerResult) => {
        if (value.hour !== undefined && value.minute !== undefined) {
          this.reminderHour = value.hour;
          this.reminderMinute = value.minute;
          await this.saveReminderSettings();
        }
      }
    });
  }

  private async saveReminderSettings(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.reminderService.init(ctx);
    const settings: ReminderSettings = {
      enabled: this.reminderEnabled,
      hour: this.reminderHour,
      minute: this.reminderMinute
    };
    await this.reminderService.updateSettings(settings);
    if (this.reminderEnabled) {
      await this.reminderService.syncDailyReminder(ctx);
      promptAction.showToast({ message: '已更新提醒设置' });
    } else {
      await this.reminderService.cancelAllReminders();
      promptAction.showToast({ message: '已关闭后台提醒' });
    }
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([CLR_TEXT])
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            router.back();
          })
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(CLR_TEXT)
          .margin({ left: 4 })
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          // 1. 临期阈值设置
          Column() {
            this.sectionHeader('临期规则')

            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('临期提醒阈值')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(CLR_TEXT)
                  Text(`剩余 ≤${this.nearExpiryDaysStr || '7'} 天标记为临期`)
                    .fontSize(12)
                    .fontColor(CLR_BRAND)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row({ space: 6 }) {
                  TextInput({ text: this.nearExpiryDaysStr, placeholder: '7' })
                    .type(InputType.Number)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(CLR_TEXT)
                    .textAlign(TextAlign.Center)
                    .backgroundColor(CLR_INPUT_BG)
                    .borderRadius(8)
                    .width(60)
                    .height(36)
                    .onChange((v: string) => {
                      this.handleThresholdChange(v.trim());
                    })

                  Text('天')
                    .fontSize(14)
                    .fontColor(CLR_TEXT_SUB)
                }
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')

              if (this.nearExpiryError !== '') {
                Text(this.nearExpiryError)
                  .fontSize(12)
                  .fontColor(CLR_DANGER)
                  .width('100%')
              }

              // 快捷天数预设
              Row({ space: 8 }) {
                ForEach(PRESET_THRESHOLDS, (preset: number) => {
                  Button(`${preset}天`)
                    .fontSize(12)
                    .fontColor(this.nearExpiryDaysStr === preset.toString() ? Color.White : CLR_TEXT)
                    .backgroundColor(this.nearExpiryDaysStr === preset.toString() ? CLR_BRAND : CLR_INPUT_BG)
                    .borderRadius(14)
                    .height(28)
                    .padding({ left: 12, right: 12 })
                    .onClick(() => {
                      this.handleThresholdChange(preset.toString());
                    })
                }, (preset: number) => preset.toString())
              }
              .width('100%')

              Text('修改后立即生效，首页与通知将按新天数自动重新分级。')
                .fontSize(12)
                .fontColor(CLR_TEXT_TIP)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(CLR_CARD)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 2. 提醒设置
          Column() {
            this.sectionHeader('提醒设置')

            Column() {
              Row() {
                Column({ space: 4 }) {
                  Text('每日临期汇总提醒')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(CLR_TEXT)
                  Text('每天定时检查物资，有临期或过期物品时推送通知')
                    .fontSize(12)
                    .fontColor(CLR_TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
                  .selectedColor(CLR_BRAND)
                  .onChange(async (isOn: boolean) => {
                    this.reminderEnabled = isOn;
                    await this.saveReminderSettings();
                  })
              }
              .width('100%')
              .padding(16)

              if (this.reminderEnabled) {
                Divider().color(CLR_BG).strokeWidth(1).margin({ left: 16, right: 16 })

                Row() {
                  Column({ space: 4 }) {
                    Text('每日提醒时间')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(CLR_TEXT)
                    Text('设定每天触发后台提醒的时间')
                      .fontSize(12)
                      .fontColor(CLR_TEXT_SUB)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Row({ space: 6 }) {
                    Text(this.formatTime(this.reminderHour, this.reminderMinute))
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(CLR_BRAND)
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([CLR_TEXT_SUB])
                  }
                  .padding({ left: 12, right: 8, top: 6, bottom: 6 })
                  .borderRadius(8)
                  .backgroundColor(CLR_INPUT_BG)
                  .onClick(() => {
                    this.pickReminderTime();
                  })
                }
                .width('100%')
                .padding(16)
              }
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(CLR_CARD)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 3. 数据备份
          Column() {
            this.sectionHeader('数据备份')

            Column({ space: 12 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('备份与恢复')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(CLR_TEXT)
                  Text('导出 JSON 备份文件自存，或从备份文件导入数据')
                    .fontSize(12)
                    .fontColor(CLR_TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')

              Row({ space: 12 }) {
                Button('导出备份')
                  .fontSize(14)
                  .fontColor(CLR_BRAND)
                  .backgroundColor(CLR_INPUT_BG)
                  .border({ width: 1, color: CLR_BRAND })
                  .borderRadius(12)
                  .height(40)
                  .layoutWeight(1)
                  .onClick(() => {
                    promptAction.showToast({ message: '备份功能开发中' });
                  })

                Button('导入备份')
                  .fontSize(14)
                  .fontColor(CLR_BRAND)
                  .backgroundColor(CLR_INPUT_BG)
                  .border({ width: 1, color: CLR_BRAND })
                  .borderRadius(12)
                  .height(40)
                  .layoutWeight(1)
                  .onClick(() => {
                    promptAction.showToast({ message: '备份功能开发中' });
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(CLR_CARD)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 4. 自定义字段管理
          Column() {
            this.sectionHeader('物资扩展')

            Column() {
              Row() {
                Column({ space: 4 }) {
                  Text('自定义字段管理')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(CLR_TEXT)
                  Text('配置物资的扩展属性与单选选项')
                    .fontSize(12)
                    .fontColor(CLR_TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(18)
                  .fontColor([CLR_TEXT_SUB])
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                router.pushUrl({ url: 'pages/CustomFieldManager' });
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(CLR_CARD)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 5. 关于
          Column() {
            this.sectionHeader('关于')

            Column() {
              Row() {
                Text('版本')
                  .fontSize(16)
                  .fontColor(CLR_TEXT)
                Blank()
                Text('1.0.0')
                  .fontSize(15)
                  .fontColor(CLR_TEXT_SUB)
              }
              .width('100%')
              .padding(16)

              Divider().color(CLR_BG).strokeWidth(1).margin({ left: 16, right: 16 })

              Row() {
                Text('数据隐私')
                  .fontSize(16)
                  .fontColor(CLR_TEXT)
                Blank()
                Text('纯端侧存储 · 零云端依赖')
                  .fontSize(13)
                  .fontColor(CLR_BRAND)
              }
              .width('100%')
              .padding(16)
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(CLR_CARD)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 30 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CLR_BG)
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(CLR_TEXT_SUB)
      .margin({ left: 4, bottom: 8 })
  }
}
