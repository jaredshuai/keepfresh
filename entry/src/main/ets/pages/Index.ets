/**
 * 首页：临期概览 + 物资列表（按到期日升序）—— 清新自然风格。
 */
import { router, promptAction, TimePickerResult } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, ExpiryLevel } from '../model/Material';
import { MaterialDb } from '../db/MaterialDb';
import {
  ExpiryStats,
  levelOf,
  levelColor,
  levelSoftColor,
  levelBadgeTextColor,
  levelText,
  remainingDays,
  statsOf
} from '../service/ExpiryService';
import { ensureNotificationEnabled, publishExpiryAlert, requestNotificationEnable } from '../service/NotificationService';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';
import { Theme } from '../common/Theme';
import { getCategoryIcon } from '../common/CategoryIcons';

enum ListFilter {
  ALL = 0,
  NEAR = 1,
  EXPIRED = 2
}

/** 每次启动只发一条汇总通知 */
let notifiedThisSession: boolean = false;

@Entry
@Component
struct Index {
  @State materials: Material[] = [];
  @State stats: ExpiryStats = { total: 0, expired: 0, near: 0, safe: 0 };
  @State filter: ListFilter = ListFilter.ALL;
  @State loading: boolean = true;
  @State showSettingsDialog: boolean = false;
  @State reminderEnabled: boolean = true;
  @State reminderHour: number = 9;
  @State reminderMinute: number = 0;
  private db: MaterialDb = MaterialDb.getInstance();

  onPageShow(): void {
    const targetFilter = AppStorage.get<string>('targetFilterLevel');
    if (targetFilter === 'NEAR') {
      this.filter = ListFilter.NEAR;
      AppStorage.setOrCreate('targetFilterLevel', undefined);
    } else if (targetFilter === 'EXPIRED') {
      this.filter = ListFilter.EXPIRED;
      AppStorage.setOrCreate('targetFilterLevel', undefined);
    }

    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadReminderSettings(ctx);

    SettingsService.getInstance().init(ctx)
      .then(() => {
        return this.db.init(ctx);
      })
      .then(() => {
        return this.refresh();
      })
      .catch((e: BusinessError) => {
        console.error(`init db failed: ${e.message}`);
        this.loading = false;
      });
    this.setupNotification(ctx);
  }

  private async loadReminderSettings(ctx: common.UIAbilityContext): Promise<void> {
    try {
      await ReminderService.getInstance().init(ctx);
      const settings: ReminderSettings = await ReminderService.getInstance().getSettings();
      this.reminderEnabled = settings.enabled;
      this.reminderHour = settings.hour;
      this.reminderMinute = settings.minute;
    } catch (e) {
      console.error(`load reminder settings failed: ${(e as BusinessError).message}`);
    }
  }

  private openReminderSettingsDialog(): void {
    this.showSettingsDialog = true;
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
    await ReminderService.getInstance().init(ctx);
    const settings: ReminderSettings = {
      enabled: this.reminderEnabled,
      hour: this.reminderHour,
      minute: this.reminderMinute
    };
    await ReminderService.getInstance().updateSettings(settings);
    await ReminderService.getInstance().syncDailyReminder(ctx);
    promptAction.showToast({ message: '已更新提醒设置' });
  }

  private async setupNotification(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const enabled: boolean = await ensureNotificationEnabled(ctx);
      if (!enabled) {
        await requestNotificationEnable(ctx);
      }
    } catch (e) {
      console.error(`setup notification failed: ${(e as BusinessError).message}`);
    }
  }

  async refresh(): Promise<void> {
    try {
      const list: Material[] = await this.db.listAll();
      this.materials = list;
      this.stats = statsOf(list);
      if (!notifiedThisSession && this.stats.near + this.stats.expired > 0) {
        notifiedThisSession = true;
        await publishExpiryAlert(this.stats.near, this.stats.expired);
      }
    } catch (e) {
      console.error(`load materials failed: ${(e as BusinessError).message}`);
    } finally {
      this.loading = false;
    }
  }

  visibleList(): Material[] {
    if (this.filter === ListFilter.NEAR) {
      return this.materials.filter((m: Material): boolean => levelOf(m) === ExpiryLevel.NEAR);
    }
    if (this.filter === ListFilter.EXPIRED) {
      return this.materials.filter((m: Material): boolean => levelOf(m) === ExpiryLevel.EXPIRED);
    }
    return this.materials;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.header()

        Row({ space: Theme.elementGap }) {
          this.statCard('全部', this.stats.total, ListFilter.ALL, Theme.textPrimary, $r('sys.symbol.archivebox'))
          this.statCard('临期', this.stats.near, ListFilter.NEAR, Theme.near, $r('sys.symbol.clock'))
          this.statCard('已过期', this.stats.expired, ListFilter.EXPIRED, Theme.expired, $r('sys.symbol.exclamationmark_triangle'))
        }
        .width('100%')
        .padding({
          left: Theme.pagePadding,
          right: Theme.pagePadding,
          bottom: Theme.cardGap
        })

        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40).color(Theme.brand)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.visibleList().length === 0) {
          this.emptyState()
        } else {
          List({ space: Theme.elementGap }) {
            ForEach(this.visibleList(), (m: Material) => {
              ListItem() {
                this.materialCard(m)
              }
            }, (m: Material) => m.id.toString())
          }
          .layoutWeight(1)
          .width('100%')
          .padding({
            left: Theme.pagePadding,
            right: Theme.pagePadding,
            top: Theme.smallGap,
            bottom: 96
          })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      Button() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(28)
          .fontColor([Theme.textWhite])
          .fontWeight(FontWeight.Bold)
      }
      .width(Theme.fabSize)
      .height(Theme.fabSize)
      .borderRadius(Theme.fabRadius)
      .backgroundColor(Theme.brand)
      .shadow(Theme.fabShadowStyle)
      .margin(Theme.pagePadding)
      .onClick(() => {
        router.pushUrl({ url: 'pages/AddItem' });
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
    .bindSheet($$this.showSettingsDialog, this.reminderSettingsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor:Theme.cardBg,
      onDisappear: () => {
        this.showSettingsDialog = false;
      }
    })
  }

  @Builder
  header() {
    Row() {
      Column() {
        Text('KeepFresh')
          .fontSize(Theme.textHero)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
        Text('让每一件物资都新鲜可见')
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)
          .margin({ top: Theme.tinyGap })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Row({ space: Theme.smallGap }) {
        this.iconButton(
          $r('sys.symbol.bell'),
          this.reminderEnabled ? Theme.brand : Theme.textSecondary,
          () => this.openReminderSettingsDialog()
        )
        this.iconButton(
          $r('sys.symbol.gearshape'),
          Theme.textPrimary,
          () => router.pushUrl({ url: 'pages/Settings' })
        )
      }
    }
    .width('100%')
    .padding({
      left: Theme.pagePadding,
      right: Theme.pagePadding,
      top: Theme.cardGap,
      bottom: Theme.elementGap
    })
  }

  @Builder
  iconButton(symbol: Resource, color: string, onClick: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([color])
    }
    .backgroundColor(Theme.cardBg)
    .width(Theme.iconBtnSize)
    .height(Theme.iconBtnSize)
    .shadow(Theme.shadowStyle)
    .onClick(onClick)
  }

  @Builder
  statCard(label: string, count: number, f: ListFilter, color: string, icon: Resource) {
    Column({ space: Theme.tinyGap }) {
      Row({ space: Theme.smallGap }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([color])
        Text(label)
          .fontSize(Theme.textSmall)
          .fontColor(Theme.textSecondary)
      }

      Text(count.toString())
        .fontSize(Theme.statNumber)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding({ top: Theme.cardPadding, bottom: Theme.cardPadding })
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.cardBg)
    .shadow(Theme.shadowStyle)
    .border(this.filter === f ? Theme.borderBrand : Theme.borderThin)
    .onClick(() => {
      this.filter = f;
    })
  }

  @Builder
  materialCard(m: Material) {
    const lv: ExpiryLevel = levelOf(m);
    const iconInfo = getCategoryIcon(m.category);

    Row() {
      // 左侧彩色状态条
      Column()
        .width(4)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(levelColor(lv))
        .margin({ right: Theme.elementGap })

      // 分类图标
      Column() {
        SymbolGlyph(iconInfo.symbol)
          .fontSize(22)
          .fontColor([Theme.brand])
      }
      .width(44)
      .height(44)
      .borderRadius(Theme.iconBtnRadius)
      .backgroundColor(iconInfo.bgColor)
      .margin({ right: Theme.elementGap })
      .justifyContent(FlexAlign.Center)

      // 物资信息
      Column() {
        Text(m.name)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${m.category} · ${m.quantity}${m.unit}`)
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)
          .margin({ top: Theme.tinyGap })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 状态徽标
      Column() {
        Text(levelText(lv, remainingDays(m)))
          .fontSize(Theme.textSmall)
          .fontWeight(FontWeight.Medium)
          .fontColor(levelBadgeTextColor(lv))
        Text(m.expiryDate)
          .fontSize(Theme.textTiny)
          .fontColor(Theme.textTertiary)
          .margin({ top: 2 })
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(Theme.badgeRadius)
      .backgroundColor(levelSoftColor(lv))
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding(Theme.cardPadding)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.cardBg)
    .shadow(Theme.shadowStyle)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
    })
  }

  @Builder
  emptyState() {
    Column({ space: Theme.elementGap }) {
      Column() {
        SymbolGlyph($r('sys.symbol.leaf'))
          .fontSize(64)
          .fontColor([Theme.brand])
          .opacity(0.4)
      }
      .width(100)
      .height(100)
      .borderRadius(50)
      .backgroundColor(Theme.brandSoft)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: Theme.smallGap })

      Text(this.stats.total === 0 ? '还没有物资' : '当前筛选下没有物资')
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary)
      Text(this.stats.total === 0 ? '点击右下角按钮，添加第一件物资吧' : '试试切换其他筛选条件')
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textTertiary)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  reminderSettingsSheet() {
    Column({ space: Theme.elementGap }) {
      Row() {
        Text('临期提醒设置')
          .fontSize(Theme.textHeadline)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
        Blank()
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })

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
          .selectedColor(Theme.brand)
          .onChange(async (isOn: boolean) => {
            this.reminderEnabled = isOn;
            await this.saveReminderSettings();
          })
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .borderRadius(Theme.cardRadius)
      .backgroundColor(Theme.inputBg)

      if (this.reminderEnabled) {
        Row() {
          Column({ space: Theme.tinyGap }) {
            Text('提醒时间')
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            Text('设定每天触发离线提醒的时间')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: Theme.smallGap }) {
            Text(this.formatTime(this.reminderHour, this.reminderMinute))
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.brand)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([Theme.textTertiary])
          }
          .padding({ left: 12, right: 10, top: 8, bottom: 8 })
          .borderRadius(Theme.inputRadius)
          .backgroundColor(Theme.cardBg)
          .onClick(() => {
            this.pickReminderTime();
          })
        }
        .width('100%')
        .padding(Theme.cardPadding)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.inputBg)
      }

      Button('完成')
        .width('100%')
        .height(44)
        .borderRadius(12)
        .backgroundColor(Theme.brand)
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .margin({ top: 8, bottom: 16 })
        .onClick(() => {
          this.showSettingsDialog = false;
        })
    }
    .width('100%')
    .padding({
      left: Theme.pagePadding,
      right: Theme.pagePadding,
      top: 12,
      bottom: 12
    })
  }
}
