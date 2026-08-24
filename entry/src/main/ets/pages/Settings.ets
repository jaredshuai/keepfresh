/**
 * 设置中心页 —— 清新自然风格。
 * 包含：临期提醒阈值配置、每日提醒时间/开关、数据备份入口、自定义字段管理入口、关于。
 */
import { router, promptAction, TimePickerResult } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';
import { BackupService, ImportPreview, ImportResult } from '../service/BackupService';
import { Theme } from '../common/Theme';

const PRESET_THRESHOLDS: number[] = [3, 7, 14, 30];

@Entry
@Component
struct Settings {
  @State nearExpiryDaysStr: string = '7';
  @State nearExpiryError: string = '';
  @State reminderEnabled: boolean = true;
  @State reminderHour: number = 8;
  @State reminderMinute: number = 0;
  @State showImportPreview: boolean = false;
  @State importPreviewData: ImportPreview | undefined = undefined;
  @State importOverwriteMode: boolean = false;
  private settingsService: SettingsService = SettingsService.getInstance();
  private reminderService: ReminderService = ReminderService.getInstance();
  private backupService: BackupService = BackupService.getInstance();

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

  // ── 备份导出/导入 ──

  private async handleExport(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.backupService.exportBackup(ctx);
  }

  private async handleImport(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const preview = await this.backupService.importBackup(ctx);
    if (preview) {
      this.importPreviewData = preview;
      this.importOverwriteMode = false;
      this.showImportPreview = true;
    }
  }

  private async confirmImport(): Promise<void> {
    if (!this.importPreviewData) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const mode: 'merge' | 'overwrite' = this.importOverwriteMode ? 'overwrite' : 'merge';
    const result: ImportResult = await this.backupService.executeImport(ctx, this.importPreviewData.data, mode);
    this.showImportPreview = false;
    this.importPreviewData = undefined;
    if (result.success) {
      promptAction.showToast({ message: result.message });
      // 刷新设置页显示（导入可能改了阈值/提醒设置）
      await this.loadAllSettings(ctx);
    } else {
      promptAction.showToast({ message: result.message });
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([Theme.textPrimary])
        }
        .backgroundColor(Theme.inputBg)
        .width(Theme.iconBtnSize)
        .height(Theme.iconBtnSize)
        .onClick(() => {
          router.back();
        })

        Text('设置')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.smallGap })

        Blank()
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding - 4,
        right: Theme.pagePadding,
        top: 12,
        bottom: 12
      })

      Scroll() {
        Column({ space: Theme.cardGap }) {
          // 1. 临期阈值设置
          this.settingsCard('临期规则', $r('sys.symbol.clock_badge_exclamationmark')) {
            Column({ space: Theme.elementGap }) {
              Row() {
                Column({ space: Theme.tinyGap }) {
                  Text('临期提醒阈值')
                    .fontSize(Theme.textBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary)
                  Text(`剩余 ≤ ${this.nearExpiryDaysStr || '7'} 天标记为临期`)
                    .fontSize(Theme.textCaption)
                    .fontColor(Theme.brand)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row({ space: Theme.smallGap }) {
                  TextInput({ text: this.nearExpiryDaysStr, placeholder: '7' })
                    .type(InputType.Number)
                    .fontSize(Theme.textBody)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.textPrimary)
                    .textAlign(TextAlign.Center)
                    .backgroundColor(Theme.inputBg)
                    .borderRadius(Theme.inputRadius)
                    .width(60)
                    .height(36)
                    .onChange((v: string) => {
                      this.handleThresholdChange(v.trim());
                    })

                  Text('天')
                    .fontSize(Theme.textCaption)
                    .fontColor(Theme.textSecondary)
                }
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')

              if (this.nearExpiryError !== '') {
                Text(this.nearExpiryError)
                  .fontSize(Theme.textSmall)
                  .fontColor(Theme.danger)
                  .width('100%')
              }

              // 快捷天数预设
              Row({ space: Theme.smallGap }) {
                ForEach(PRESET_THRESHOLDS, (preset: number) => {
                  Button(`${preset}天`)
                    .fontSize(Theme.textSmall)
                    .fontColor(this.nearExpiryDaysStr === preset.toString() ? Color.White : Theme.textPrimary)
                    .backgroundColor(this.nearExpiryDaysStr === preset.toString() ? Theme.brand : Theme.inputBg)
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
                .fontSize(Theme.textSmall)
                .fontColor(Theme.textTertiary)
                .width('100%')
            }
            .width('100%')
          }

          // 2. 提醒设置
          this.settingsCard('提醒设置', $r('sys.symbol.bell_badge')) {
            Column() {
              this.settingsRow('每日临期汇总提醒', '每天定时检查物资，有临期或过期物品时推送通知', () => {
                Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
                  .selectedColor(Theme.brand)
                  .onChange(async (isOn: boolean) => {
                    this.reminderEnabled = isOn;
                    await this.saveReminderSettings();
                  })
              })

              if (this.reminderEnabled) {
                Divider().color(Theme.divider).strokeWidth(1).margin({ left: Theme.cardPadding, right: Theme.cardPadding })

                this.settingsRow('每日提醒时间', '设定每天触发后台提醒的时间', () => {
                  Row({ space: Theme.smallGap }) {
                    Text(this.formatTime(this.reminderHour, this.reminderMinute))
                      .fontSize(Theme.textBody)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.brand)
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([Theme.textTertiary])
                  }
                  .padding({ left: 12, right: 8, top: 6, bottom: 6 })
                  .borderRadius(Theme.inputRadius)
                  .backgroundColor(Theme.inputBg)
                  .onClick(() => {
                    this.pickReminderTime();
                  })
                })
              }
            }
            .width('100%')
          }

          // 3. 数据备份
          this.settingsCard('数据备份', $r('sys.symbol.arrow_up_arrow_down_square')) {
            Column({ space: Theme.elementGap }) {
              Text('备份与恢复')
                .fontSize(Theme.textBody)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
                .width('100%')
              Text('导出 JSON 备份文件自存，或从备份文件导入数据')
                .fontSize(Theme.textCaption)
                .fontColor(Theme.textSecondary)
                .width('100%')

              Row({ space: Theme.elementGap }) {
                Button('导出备份')
                  .fontSize(Theme.textCaption)
                  .fontColor(Theme.brand)
                  .backgroundColor(Theme.brandSoft)
                  .borderRadius(Theme.inputRadius)
                  .height(40)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.handleExport();
                  })

                Button('导入备份')
                  .fontSize(Theme.textCaption)
                  .fontColor(Theme.brand)
                  .backgroundColor(Theme.brandSoft)
                  .borderRadius(Theme.inputRadius)
                  .height(40)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.handleImport();
                  })
              }
              .width('100%')
              .margin({ top: Theme.smallGap })
            }
            .width('100%')
          }

          // 4. 自定义字段管理
          this.settingsCard('物资扩展', $r('sys.symbol.list_bullet_rectangle')) {
            this.settingsRow('自定义字段管理', '配置物资的扩展属性与单选选项', () => {
              Row({ space: Theme.smallGap }) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(18)
                  .fontColor([Theme.textTertiary])
              }
            }, () => {
              router.pushUrl({ url: 'pages/CustomFieldManager' });
            })
          }

          // 5. 关于
          this.settingsCard('关于', $r('sys.symbol.info_circle')) {
            Column() {
              this.settingsRow('版本', '', () => {
                Text('1.0.0')
                  .fontSize(Theme.textSubhead)
                  .fontColor(Theme.textTertiary)
              })

              Divider().color(Theme.divider).strokeWidth(1).margin({ left: Theme.cardPadding, right: Theme.cardPadding })

              this.settingsRow('数据隐私', '', () => {
                Text('纯端侧存储 · 零云端依赖')
                  .fontSize(Theme.textCaption)
                  .fontColor(Theme.brand)
              })
            }
            .width('100%')
          }

          // 底部安全区
          Column().width('100%').height(20)
        }
        .width('100%')
        .padding({
          left: Theme.pagePadding,
          right: Theme.pagePadding,
          top: 4,
          bottom: 30
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
    .bindSheet($$this.showImportPreview, this.importPreviewSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: Theme.cardBg,
      onDisappear: () => {
        this.showImportPreview = false;
        this.importPreviewData = undefined;
      }
    })
  }

  @Builder
  settingsCard(title: string, icon: Resource, content: () => void) {
    Column({ space: Theme.smallGap }) {
      // 卡片标题
      Row({ space: Theme.smallGap }) {
        SymbolGlyph(icon)
          .fontSize(16)
          .fontColor([Theme.brand])
        Text(title)
          .fontSize(Theme.textCaption)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')
      .padding({ left: 4 })

      Column() {
        content()
      }
      .width('100%')
      .padding(Theme.cardPadding - 4)
      .borderRadius(Theme.cardRadius)
      .backgroundColor(Theme.cardBg)
      .shadow(Theme.shadowStyle)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  settingsRow(label: string, desc: string, trailing: () => void, onClick?: () => void) {
    Row() {
      Column({ space: Theme.tinyGap }) {
        Text(label)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        if (desc !== '') {
          Text(desc)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      trailing()
    }
    .width('100%')
    .padding(Theme.smallGap)
    .onClick(onClick ? onClick : () => {})
  }

  @Builder
  importPreviewSheet() {
    Column({ space: Theme.elementGap }) {
      Row() {
        Text('导入预览')
          .fontSize(Theme.textHeadline)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
        Blank()
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })

      if (this.importPreviewData) {
        Column({ space: Theme.elementGap }) {
          this.previewRow('备份文件包含', `${this.importPreviewData.data.materials.length} 件物资`, Theme.textPrimary)
          this.previewRow('将新增', `${this.importPreviewData.addCount} 件`, Theme.brand)
          this.previewRow('将覆盖', `${this.importPreviewData.overwriteCount} 件`, Theme.danger)
        }
        .width('100%')
        .padding(Theme.cardPadding)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.inputBg)

        // 清空后导入选项
        Row() {
          Column({ space: Theme.tinyGap }) {
            Text('清空后导入')
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            Text('删除所有现有物资，再导入备份数据')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.importOverwriteMode })
            .selectedColor(Theme.danger)
            .onChange((isOn: boolean) => {
              this.importOverwriteMode = isOn;
            })
        }
        .width('100%')
        .padding(Theme.cardPadding)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.inputBg)

        if (this.importOverwriteMode) {
          Text('⚠️ 开启后将删除所有现有物资，此操作不可撤销')
            .fontSize(Theme.textSmall)
            .fontColor(Theme.danger)
            .width('100%')
        }
      }

      Row({ space: Theme.elementGap }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor(Theme.inputBg)
          .fontColor(Theme.textPrimary)
          .fontSize(Theme.textBody)
          .onClick(() => {
            this.showImportPreview = false;
            this.importPreviewData = undefined;
          })

        Button('确认导入')
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor(Theme.brand)
          .fontColor(Color.White)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.confirmImport();
          })
      }
      .width('100%')
      .margin({ top: 8, bottom: 16 })
    }
    .width('100%')
    .padding({
      left: Theme.pagePadding,
      right: Theme.pagePadding,
      top: 12,
      bottom: 12
    })
  }

  @Builder
  previewRow(label: string, value: string, valueColor: string) {
    Row() {
      Text(label)
        .fontSize(Theme.textSubhead)
        .fontColor(Theme.textSecondary)
      Blank()
      Text(value)
        .fontSize(Theme.textSubhead)
        .fontColor(valueColor)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
  }
}
