/**
 * 设置中心页 —— 包豪斯（Bauhaus）风格。
 * 包含：临期提醒阈值配置、每日提醒时间/开关、数据备份入口、自定义字段管理入口、关于。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';
import { BackupService, ImportPreview, ImportResult } from '../service/BackupService';
import { Theme } from '../common/Theme';
import { UsageService } from '../service/UsageService';
import { HardShadowBox, HardShadowCard } from '../common/HardShadow';

interface TimePickerResult {
  hour?: number;
  minute?: number;
}

const PRESET_THRESHOLDS: number[] = [3, 7, 14, 30];

/* ============================================================
 * SettingsRow 独立组件：@BuilderParam 模式支持尾随闭包 UI 语法
 * ============================================================ */
@Builder
function emptyTrailingBuilder(): void {}

@Component
struct SettingsRowComponent {
  label: string = '';
  desc: string = '';
  handleRowClick?: () => void = undefined;
  @BuilderParam trailing: () => void = emptyTrailingBuilder;

  build() {
    Row() {
      Column({ space: Theme.tinyGap }) {
        Text(this.label)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        if (this.desc !== '') {
          Text(this.desc)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.trailing()
    }
    .width('100%')
    .padding({
      left: Theme.cardPadding,
      right: Theme.cardPadding,
      top: Theme.smallGap,
      bottom: Theme.smallGap
    })
    .onClick(this.handleRowClick ? this.handleRowClick : () => {})
  }
}

@Entry
@Component
struct Settings {
  @StorageProp('avoidTopVp') avoidTopVp: number = 0;
  @StorageProp('avoidBottomVp') avoidBottomVp: number = 0;
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

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error(`show toast failed: ${(e as BusinessError).message}`);
    }
  }

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
    try {
      const ok = await this.settingsService.updateNearExpiryDays(days);
      if (ok) {
        let reminderHint = '';
        try {
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          await this.reminderService.syncDailyReminder(ctx);
        } catch (syncErr) {
          // 阈值此刻已持久化成功；提醒重同步失败（如未授予通知权限导致
          // 代理提醒配额为 0）只附提示，不得误报为「保存失败」
          console.error(`threshold saved but reminder resync failed: ${(syncErr as BusinessError).message}`);
          reminderHint = '，但提醒同步失败（检查通知权限）';
        }
        this.toast(`已设置临期阈值为 ${days} 天${reminderHint}`);
      }
    } catch (e) {
      console.error(`update threshold failed: ${(e as BusinessError).message}`);
      // 失败后回滚 UI 状态到持久化值并给出提示，避免显示为未保存值
      try {
        const savedDays = await this.settingsService.getNearExpiryDays();
        this.nearExpiryDaysStr = savedDays.toString();
      } catch (_) {
        /* 回滚失败至少给出失败提示 */
      }
      this.toast('阈值保存失败，请重试');
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
    try {
      const settings: ReminderSettings = {
        enabled: this.reminderEnabled,
        hour: this.reminderHour,
        minute: this.reminderMinute
      };
      // 编辑管线唯一入口在 ReminderService.editSettings（与首页共用，C5）
      this.toast(await this.reminderService.editSettings(ctx, settings));
    } catch (e) {
      console.error(`save reminder settings failed: ${(e as BusinessError).message}`);
      // 失败后回滚 UI 状态到持久化值并给出提示，避免开关/时间看起来成功但未保存（评审找回）
      try {
        const saved: ReminderSettings = await this.reminderService.getSettings();
        this.reminderEnabled = saved.enabled;
        this.reminderHour = saved.hour;
        this.reminderMinute = saved.minute;
      } catch (_) {
        /* 回滚失败至少给出失败提示 */
      }
      this.toast('提醒设置保存失败，请重试');
    }
  }

  // ── 备份导出/导入 ──

  private async handleExport(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.backupService.exportBackup(ctx, this.getUIContext());
  }

  private async handleExportUsageLog(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await UsageService.getInstance().init(ctx);
    await UsageService.getInstance().exportUsageLog(ctx, this.getUIContext());
  }

  private async handleImport(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const preview = await this.backupService.importBackup(ctx, this.getUIContext());
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
    try {
      const result: ImportResult = await this.backupService.executeImport(ctx, this.importPreviewData.data, mode);
      this.showImportPreview = false;
      this.importPreviewData = undefined;
      if (result.success) {
        // 有 warnings 时拼接展示，给用户可见重试路径
        const extra = (result.warnings && result.warnings.length > 0)
          ? `。${result.warnings.join('；')}`
          : '';
        this.toast(result.message + extra);
        // 刷新设置页显示（导入可能改了阈值/提醒设置）
        await this.loadAllSettings(ctx);
      } else {
        const extra = (result.warnings && result.warnings.length > 0)
          ? `（${result.warnings.join('；')}）`
          : '';
        this.toast(result.message + extra);
      }
    } catch (e) {
      console.error(`execute import failed: ${(e as BusinessError).message}`);
      this.showImportPreview = false;
      this.importPreviewData = undefined;
      this.toast('导入失败，请重试');
    }
  }

  build() {
    Column() {
      // ─── 顶部导航：返回图标按钮 + "设置" 标题 ───
      Row() {
        Stack() {
          this.iconButton(
            $r('sys.symbol.chevron_left'),
            () => {
              this.getUIContext().getRouter().back();
            }
          )
        }
        .margin({ right: Theme.smallGap })

        Text('设置')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .letterSpacing(0.5)

        Blank()
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding - Theme.hardShadowOffset,
        right: Theme.pagePadding,
        top: 12,
        bottom: 12
      })

      Scroll() {
        Column({ space: Theme.cardGap }) {
          // ─── 1. 临期阈值设置 ───
          Column({ space: Theme.smallGap }) {
            // 卡片标题：左图标 + 文字
            Row({ space: Theme.smallGap }) {
              Column() {
                SymbolGlyph($r('sys.symbol.clock'))
                  .fontSize(14)
                  .fontColor([Theme.textWhite])
              }
              .width(20)
              .height(20)
              .backgroundColor(Theme.yellowDark)
              .border(Theme.borderThin)
              .justifyContent(FlexAlign.Center)

              Text('临期规则')
                .fontSize(Theme.textCaption)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
                .letterSpacing(0.5)
            }
            .width('100%')
            .padding({ left: 4 })

            // 卡片主体：硬阴影 + 黑边
            HardShadowCard({shadowMode: 0}) {

              Column({ space: Theme.elementGap }) {
                // 阈值输入行
                Row() {
                  Column({ space: Theme.tinyGap }) {
                    Text('临期提醒阈值')
                      .fontSize(Theme.textBody)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.textPrimary)
                    Text(`剩余 ≤ ${this.nearExpiryDaysStr || '7'} 天标记为临期`)
                      .fontSize(Theme.textCaption)
                      .fontColor(Theme.yellowDark)
                      .fontWeight(FontWeight.Medium)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Row({ space: Theme.smallGap }) {
                    HardShadowBox({boxWidth: 60, boxHeight: 36}) {

                      TextInput({ text: this.nearExpiryDaysStr, placeholder: '7' })
                        .type(InputType.Number)
                        .borderRadius(Theme.inputRadius)
                        .fontSize(Theme.textBody)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.textPrimary)
                        .textAlign(TextAlign.Center)
                        .backgroundColor(Theme.inputBg)
                        .border(Theme.borderThin)
                        .placeholderColor(Theme.textTertiary)
                        .width(60)
                        .height(36)
                        .onChange((v: string) => {
                          this.handleThresholdChange(v.trim());
                        })
                    }

                    Text('天')
                      .fontSize(Theme.textCaption)
                      .fontColor(Theme.textSecondary)
                      .fontWeight(FontWeight.Medium)
                  }
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')

                if (this.nearExpiryError !== '') {
                  Text(this.nearExpiryError)
                    .fontSize(Theme.textSmall)
                    .fontColor(Theme.danger)
                    .fontWeight(FontWeight.Medium)
                    .width('100%')
                }

                // 快捷天数预设 Chip
                Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(PRESET_THRESHOLDS, (preset: number) => {
                    Stack() {
                      this.chipButton(
                        `${preset}天`,
                        preset.toString(),
                        () => {
                          this.handleThresholdChange(preset.toString());
                        }
                      )
                    }
                    .margin({ right: Theme.smallGap, bottom: Theme.smallGap })
                  }, (preset: number) => preset.toString())
                }
                .width('100%')

                // 说明文字
                Text('修改后立即生效，首页与通知将按新天数自动重新分级。')
                  .fontSize(Theme.textSmall)
                  .fontColor(Theme.textTertiary)
                  .width('100%')
              }
              .width('100%')
              .padding(Theme.cardPadding)
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // ─── 2. 提醒设置 ───
          Column({ space: Theme.smallGap }) {
            Row({ space: Theme.smallGap }) {
              Column() {
                SymbolGlyph($r('sys.symbol.bell'))
                  .fontSize(14)
                  .fontColor([Theme.textWhite])
              }
              .width(20)
              .height(20)
              .backgroundColor(Theme.near)
              .border(Theme.borderThin)
              .justifyContent(FlexAlign.Center)

              Text('提醒设置')
                .fontSize(Theme.textCaption)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
                .letterSpacing(0.5)
            }
            .width('100%')
            .padding({ left: 4 })

            HardShadowCard({shadowMode: 0}) {

              Column() {
                SettingsRowComponent({
                  label: '每日临期汇总提醒',
                  desc: '每天定时检查物资，有临期或过期物品时推送通知'
                }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
                    .selectedColor(Theme.yellowDark)
                    .onChange(async (isOn: boolean) => {
                      this.reminderEnabled = isOn;
                      await this.saveReminderSettings();
                    })
                }

                if (this.reminderEnabled) {
                  Divider().color(Theme.divider).strokeWidth(1)

                  SettingsRowComponent({
                    label: '每日提醒时间',
                    desc: '设定每天触发后台提醒的时间'
                  }) {
                    Stack() {
                      Column()
                        .backgroundColor(Theme.ink)
                        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

                      Row({ space: Theme.smallGap }) {
                        Text(this.formatTime(this.reminderHour, this.reminderMinute))
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
                        this.pickReminderTime();
                      })
                    }
                    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
                  }
                }
              }
              .width('100%')
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // ─── 3. 数据备份 ───
          Column({ space: Theme.smallGap }) {
            Row({ space: Theme.smallGap }) {
              Column() {
                SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                  .fontSize(14)
                  .fontColor([Theme.textWhite])
              }
              .width(20)
              .height(20)
              .backgroundColor(Theme.safe)
              .border(Theme.borderThin)
              .justifyContent(FlexAlign.Center)

              Text('数据备份')
                .fontSize(Theme.textCaption)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
                .letterSpacing(0.5)
            }
            .width('100%')
            .padding({ left: 4 })

            HardShadowCard({shadowMode: 0}) {

              Column({ space: Theme.elementGap }) {
                Column({ space: Theme.tinyGap }) {
                  Text('备份与恢复')
                    .fontSize(Theme.textBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.textPrimary)
                    .width('100%')
                  Text('导出 JSON 备份文件自存，或从备份文件导入数据')
                    .fontSize(Theme.textCaption)
                    .fontColor(Theme.textSecondary)
                    .width('100%')
                }

                Row({ space: Theme.elementGap }) {
                  this.secondaryButton('导出备份', () => {
                    this.handleExport();
                  })

                  this.secondaryButton('导入备份', () => {
                    this.handleImport();
                  })
                }
                .width('100%')
                .margin({ top: Theme.smallGap })

                // 用 Row 包裹：secondaryButton 内含 layoutWeight(1)（横向平分宽度），
                // 若包在 Column 里 weight 会作用到主轴高度，把按钮拉伸到视口剩余高度
                Row() {
                  this.secondaryButton('导出使用日志（dogfood）', () => {
                    this.handleExportUsageLog();
                  })
                }
                .width('100%')
                .margin({ top: Theme.smallGap })
              }
              .width('100%')
              .padding(Theme.cardPadding)
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // ─── 4. 物资扩展与分类管理 ───
          Column({ space: Theme.smallGap }) {
            Row({ space: Theme.smallGap }) {
              Column() {
                SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                  .fontSize(14)
                  .fontColor([Theme.textWhite])
              }
              .width(20)
              .height(20)
              .backgroundColor(Theme.expired)
              .border(Theme.borderThin)
              .justifyContent(FlexAlign.Center)

              Text('物资扩展与组织')
                .fontSize(Theme.textCaption)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
                .letterSpacing(0.5)
            }
            .width('100%')
            .padding({ left: 4 })

            HardShadowCard({shadowMode: 0}) {

              Column() {
                SettingsRowComponent({
                  label: '自定义字段管理',
                  desc: '配置物资的扩展属性与单选选项',
                  handleRowClick: () => {
                    this.getUIContext().getRouter().pushUrl({ url: 'pages/CustomFieldManager' });
                  }
                }) {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([Theme.textTertiary])
                }

                Divider().color(Theme.divider).strokeWidth(1)

                SettingsRowComponent({
                  label: '分类 / 位置 / 单位管理',
                  desc: '新增 / 重命名 / 排序自定义分类、存放位置和数量单位',
                  handleRowClick: () => {
                    this.getUIContext().getRouter().pushUrl({ url: 'pages/CategoryManager' });
                  }
                }) {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([Theme.textTertiary])
                }
              }
              .width('100%')
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // ─── 5. 数据安全（回收站） ───
          Column({ space: Theme.smallGap }) {
            Row({ space: Theme.smallGap }) {
              Column() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(14)
                  .fontColor([Theme.textWhite])
              }
              .width(20)
              .height(20)
              .backgroundColor(Theme.textSecondary)
              .border(Theme.borderThin)
              .justifyContent(FlexAlign.Center)

              Text('数据安全')
                .fontSize(Theme.textCaption)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
                .letterSpacing(0.5)
            }
            .width('100%')
            .padding({ left: 4 })

            HardShadowCard({shadowMode: 0}) {

              Column() {
                SettingsRowComponent({
                  label: '回收站',
                  desc: '查看已删除的物资，恢复或彻底删除',
                  handleRowClick: () => {
                    this.getUIContext().getRouter().pushUrl({ url: 'pages/RecycleBin' });
                  }
                }) {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([Theme.textTertiary])
                }
              }
              .width('100%')
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // ─── 6. 关于 ───
          Column({ space: Theme.smallGap }) {
            Row({ space: Theme.smallGap }) {
              Column() {
                SymbolGlyph($r('sys.symbol.info_circle'))
                  .fontSize(14)
                  .fontColor([Theme.textWhite])
              }
              .width(20)
              .height(20)
              .backgroundColor(Theme.ink)
              .border(Theme.borderThin)
              .justifyContent(FlexAlign.Center)

              Text('关于')
                .fontSize(Theme.textCaption)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
                .letterSpacing(0.5)
            }
            .width('100%')
            .padding({ left: 4 })

            HardShadowCard({shadowMode: 0}) {

              Column() {
                SettingsRowComponent({
                  label: '版本',
                  desc: ''
                }) {
                  Text('1.0.0')
                    .fontSize(Theme.textSubhead)
                    .fontColor(Theme.textTertiary)
                    .fontWeight(FontWeight.Medium)
                }

                Divider().color(Theme.divider).strokeWidth(1)

                SettingsRowComponent({
                  label: '数据隐私',
                  desc: ''
                }) {
                  Text('纯端侧存储 · 零云端依赖')
                    .fontSize(Theme.textCaption)
                    .fontColor(Theme.yellowDark)
                    .fontWeight(FontWeight.Bold)
                }
              }
              .width('100%')
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

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
    .padding({ top: this.avoidTopVp, bottom: this.avoidBottomVp })
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

  /* ============================================================
   * 图标按钮：白底黑边 40x40 + 硬阴影
   * ============================================================ */
  @Builder
  iconButton(symbol: Resource, onClick: () => void) {
    HardShadowBox({boxWidth: Theme.iconBtnSize, boxHeight: Theme.iconBtnSize, onBoxClick: onClick}) {

      Column() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([Theme.ink])
      }
      .width(Theme.iconBtnSize)
      .height(Theme.iconBtnSize)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .justifyContent(FlexAlign.Center)
    }
  }

  /* ============================================================
   * Chip 按钮：未选中白底黑边黑字，选中深黄底白字黑边 + 硬阴影
   * ============================================================ */
  @Builder
  chipButton(label: string, value: string, onClick: () => void) {
    Stack() {
      Column()
        .height(Theme.chipHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Row() {
        Text(label)
          .fontSize(Theme.textSmall)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.nearExpiryDaysStr === value ? Theme.textWhite : Theme.textPrimary)
      }
      .height(Theme.chipHeight)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.nearExpiryDaysStr === value ? Theme.yellowDark : Theme.cardBg)
      .border(Theme.borderThin)
      .justifyContent(FlexAlign.Center)
    }
    .height(Theme.chipHeight + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(onClick)
  }

  /* ============================================================
   * 次要按钮：白底 + 黑字 + 黑边 + 硬阴影
   * ============================================================ */
  @Builder
  secondaryButton(label: string, onClick: () => void) {
    Stack() {
      // 墨影层与 Stack 同宽（Stack 子层不参与父 weight 分配，layoutWeight 是哑弹——#layoutweight-axis）
      Column()
        .width('100%')
        .height(40)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Row() {
        Text(label)
          .fontSize(Theme.textCaption)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
      }
      .layoutWeight(1)
      .height(40)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(40 + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(onClick)
  }

  /* ============================================================
   * 主要按钮：深黄底 + 白字 + 黑边 + 硬阴影
   * ============================================================ */
  @Builder
  primaryButton(label: string, onClick: () => void) {
    Stack() {
      // 墨影层与 Stack 同宽（Stack 子层不参与父 weight 分配，layoutWeight 是哑弹——#layoutweight-axis）
      Column()
        .width('100%')
        .height(44)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Row() {
        Text(label)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textWhite)
      }
      .layoutWeight(1)
      .height(44)
      .backgroundColor(Theme.yellowDark)
      .border(Theme.borderThin)
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(44 + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(onClick)
  }

  /* ============================================================
   * 导入预览 Sheet：卡片黑边硬阴影 + 深黄/白色按钮
   * ============================================================ */
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
        // 预览卡片
        HardShadowCard({shadowMode: 0}) {

          Column({ space: Theme.elementGap }) {
            this.previewRow('备份文件包含', `${this.importPreviewData.data.materials.length} 件物资`, Theme.textPrimary)
            this.previewRow('将新增', `${this.importPreviewData.addCount} 件`, Theme.safe)
            this.previewRow('将覆盖', `${this.importPreviewData.overwriteCount} 件`, Theme.danger)
          }
          .width('100%')
          .padding(Theme.cardPadding)
          .backgroundColor(Theme.cardBg)
          .border(Theme.borderThin)
        }

        // 清空后导入选项卡片
        HardShadowCard({shadowMode: 0}) {

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
          .backgroundColor(Theme.cardBg)
          .border(Theme.borderThin)
        }

        if (this.importOverwriteMode) {
          Text('⚠️ 开启后将删除所有现有物资，此操作不可撤销')
            .fontSize(Theme.textSmall)
            .fontColor(Theme.danger)
            .fontWeight(FontWeight.Medium)
            .width('100%')
        }
      }

      Row({ space: Theme.elementGap }) {
        this.secondaryButton('取消', () => {
          this.showImportPreview = false;
          this.importPreviewData = undefined;
        })

        this.primaryButton('确认导入', () => {
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
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
  }
}
