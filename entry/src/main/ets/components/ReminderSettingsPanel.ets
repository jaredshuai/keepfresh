/**
 * 提醒设置面板（候选 3 深化）：状态读写 + 时间选择 + editSettings 保存（含失败回滚）
 * 收拢为一个自包含组件；Index 底部 Sheet 与 Settings 页都只挂载它。
 *
 * 此前两处各养一套 @State + 保存管线且已漂移：
 * - 失败回滚仅 Settings 有（评审找回），Index 缺失；
 * - 默认时间不一致（Settings 初始 8 点 / Index 初始 9 点 / 服务端默认 9 点）；
 * - 文案分叉（「离线提醒」vs「后台提醒」；域术语为后台代理提醒，统一后者）。
 * 编辑管线唯一入口仍是 ReminderService.editSettings（C5），本组件只统一承载它的 UI。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { Theme } from '../common/Theme';
import { HardShadowCard } from '../common/HardShadow';

interface TimePickerResult {
  hour?: number;
  minute?: number;
}

@Component
export struct ReminderSettingsPanel {
  @State reminderEnabled: boolean = true;
  @State hour: number = 9;   // 与 ReminderService 默认 9:00 对齐
  @State minute: number = 0;
  private service: ReminderService = ReminderService.getInstance();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.service.init(ctx)
      .then(() => {
        return this.service.getSettings();
      })
      .then((s: ReminderSettings) => {
        this.reminderEnabled = s.enabled;
        this.hour = s.hour;
        this.minute = s.minute;
      })
      .catch((e: BusinessError) => {
        console.error(`load reminder settings failed: ${e.message}`);
      });
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error(`show toast failed: ${(e as BusinessError).message}`);
    }
  }

  private formatTime(hour: number, minute: number): string {
    const h = hour < 10 ? `0${hour}` : `${hour}`;
    const m = minute < 10 ? `0${minute}` : `${minute}`;
    return `${h}:${m}`;
  }

  private pickTime(): void {
    const selectedDate = new Date();
    selectedDate.setHours(this.hour, this.minute, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selectedDate,
      useMilitaryTime: true,
      onAccept: async (value: TimePickerResult) => {
        if (value.hour !== undefined && value.minute !== undefined) {
          this.hour = value.hour;
          this.minute = value.minute;
          await this.save();
        }
      }
    });
  }

  private async save(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const settings: ReminderSettings = {
        enabled: this.reminderEnabled,
        hour: this.hour,
        minute: this.minute
      };
      this.toast(await this.service.editSettings(ctx, settings));
    } catch (e) {
      console.error(`save reminder settings failed: ${(e as BusinessError).message}`);
      // 失败后回滚 UI 状态到持久化值，避免开关/时间看起来成功但未保存（评审找回，两处统一）
      try {
        const saved: ReminderSettings = await this.service.getSettings();
        this.reminderEnabled = saved.enabled;
        this.hour = saved.hour;
        this.minute = saved.minute;
      } catch (_) {
        /* 回滚失败至少给出失败提示 */
      }
      this.toast('提醒设置保存失败，请重试');
    }
  }

  build() {
    HardShadowCard({shadowMode: 0}) {
      Column() {
        // 开关行
        Row() {
          Column({ space: Theme.tinyGap }) {
            Text('每日临期汇总提醒')
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            Text('每天定时检查物资，有临期或过期物品时推送通知')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
            .selectedColor(Theme.yellowDark)
            .onChange(async (isOn: boolean) => {
              this.reminderEnabled = isOn;
              await this.save();
            })
        }
        .width('100%')
        .padding({
          left: Theme.cardPadding,
          right: Theme.cardPadding,
          top: Theme.smallGap,
          bottom: Theme.smallGap
        })

        if (this.reminderEnabled) {
          Divider().color(Theme.divider).strokeWidth(1)

          // 时间行
          Row() {
            Column({ space: Theme.tinyGap }) {
              Text('每日提醒时间')
                .fontSize(Theme.textBody)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
              Text('设定每天触发后台提醒的时间')
                .fontSize(Theme.textCaption)
                .fontColor(Theme.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Stack() {
              Column()
                .backgroundColor(Theme.ink)
                .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

              Row({ space: Theme.smallGap }) {
                Text(this.formatTime(this.hour, this.minute))
                  .fontSize(Theme.textBody)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.yellowDark)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([Theme.textTertiary])
              }
              .padding({ left: 12, right: 8, top: 6, bottom: 6 })
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
              .onClick(() => {
                this.pickTime();
              })
            }
            .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
          }
          .width('100%')
          .padding({
            left: Theme.cardPadding,
            right: Theme.cardPadding,
            top: Theme.smallGap,
            bottom: Theme.smallGap
          })
        }
      }
      .width('100%')
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
    }
  }
}
