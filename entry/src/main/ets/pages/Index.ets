/**
 * 首页：包豪斯风格 —— 变体 C 状态分组布局（已过期 / 临期 / 安全折叠）
 * 几何状态语言：过期=红色圆形，临期=橙色三角形，安全=蓝绿正方形
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
  remainingDays,
  statsOf
} from '../service/ExpiryService';
import { ensureNotificationEnabled, publishExpiryAlert, requestNotificationEnable } from '../service/NotificationService';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';
import { Theme } from '../common/Theme';
import { getCategoryIcon } from '../common/CategoryIcons';

/** 每次启动只发一条汇总通知 */
let notifiedThisSession: boolean = false;

@Entry
@Component
struct Index {
  @State materials: Material[] = [];
  @State stats: ExpiryStats = { total: 0, expired: 0, near: 0, safe: 0 };
  @State loading: boolean = true;
  @State showSettingsDialog: boolean = false;
  @State reminderEnabled: boolean = true;
  @State reminderHour: number = 9;
  @State reminderMinute: number = 0;
  @State safeCollapsed: boolean = true;   // 安全组默认折叠
  private db: MaterialDb = MaterialDb.getInstance();

  onPageShow(): void {
    const targetFilter = AppStorage.get<string>('targetFilterLevel');
    if (targetFilter === 'NEAR' || targetFilter === 'EXPIRED') {
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

  /** 分组辅助：按级别分组并按剩余天数升序（过期项负天数越小越靠前） */
  private groupByLevel(): { expired: Material[]; near: Material[]; safe: Material[] } {
    const expired: Material[] = [];
    const near: Material[] = [];
    const safe: Material[] = [];
    for (let i = 0; i < this.materials.length; i++) {
      const m = this.materials[i];
      const lv = levelOf(m);
      if (lv === ExpiryLevel.EXPIRED) expired.push(m);
      else if (lv === ExpiryLevel.NEAR) near.push(m);
      else safe.push(m);
    }
    const cmp = (a: Material, b: Material): number => remainingDays(a) - remainingDays(b);
    expired.sort(cmp);
    near.sort(cmp);
    safe.sort(cmp);
    return { expired, near, safe };
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.header()

        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40).color(Theme.ink)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.materials.length === 0) {
          this.emptyState()
        } else {
          Scroll() {
            Column({ space: Theme.cardGap }) {
              const groups = this.groupByLevel();

              // ─── 已过期组（红色圆形） ───
              if (groups.expired.length > 0) {
                this.groupHeader('已过期', ExpiryLevel.EXPIRED, groups.expired.length)
                Column({ space: Theme.smallGap }) {
                  ForEach(groups.expired, (m: Material) => {
                    this.expiredCard(m)
                  }, (m: Material) => m.id.toString())
                }
                .width('100%')
              }

              // ─── 临期组（橙色三角形） ───
              if (groups.near.length > 0) {
                this.groupHeader('临期', ExpiryLevel.NEAR, groups.near.length)
                  .margin({ top: groups.expired.length > 0 ? 0 : 0 })
                Column({ space: Theme.smallGap }) {
                  ForEach(groups.near, (m: Material) => {
                    this.materialCard(m)
                  }, (m: Material) => m.id.toString())
                }
                .width('100%')
              }

              // ─── 安全组（蓝绿正方形，可折叠） ───
              if (groups.safe.length > 0) {
                this.groupHeaderWithToggle('安全', ExpiryLevel.SAFE, groups.safe.length)
                if (!this.safeCollapsed) {
                  Column({ space: Theme.smallGap }) {
                    ForEach(groups.safe, (m: Material) => {
                      this.materialCard(m)
                    }, (m: Material) => m.id.toString())
                  }
                  .width('100%')
                }
              }

              // 底部留出 FAB 空间
              Column().width('100%').height(96)
            }
            .width('100%')
            .padding({
              left: Theme.pagePadding,
              right: Theme.pagePadding,
              top: Theme.smallGap
            })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      // FAB：深黄 + 纯黑边框 + 硬阴影
      this.hardShadowFab(() => {
        router.pushUrl({ url: 'pages/AddItem' });
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
    .bindSheet($$this.showSettingsDialog, this.reminderSettingsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: Theme.cardBg,
      onDisappear: () => {
        this.showSettingsDialog = false;
      }
    })
  }

  /* ============================================================
   * 顶部：品牌名 + 总览统计（N项·1过期·3临期）+ 图标按钮
   * ============================================================ */
  @Builder
  header() {
    Row() {
      Column({ space: Theme.tinyGap }) {
        Row() {
          Text('KeepFresh.')
            .fontSize(Theme.textHero)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary)
            .letterSpacing(0.5)
        }
        if (this.stats.total > 0) {
          Row({ space: 4 }) {
            Text(`${this.stats.total}项`)
              .fontSize(Theme.textCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textSecondary)
            Text('·')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textTertiary)
            Text(`${this.stats.expired}过期`)
              .fontSize(Theme.textCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.expired)
            Text('·')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textTertiary)
            Text(`${this.stats.near}临期`)
              .fontSize(Theme.textCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.near)
          }
        } else {
          Text('让每一件物资新鲜可见')
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Row({ space: Theme.smallGap }) {
        this.iconButton(
          $r('sys.symbol.bell'),
          () => this.openReminderSettingsDialog()
        )
        this.iconButton(
          $r('sys.symbol.gearshape'),
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

  /* ============================================================
   * 分组 header
   * ============================================================ */
  @Builder
  groupHeader(title: string, level: ExpiryLevel, count: number) {
    Row({ space: Theme.smallGap }) {
      this.geoShape(level)
      Text(title)
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
        .letterSpacing(0.5)
      Text(`${count}`)
        .fontSize(Theme.textCaption)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textTertiary)
    }
    .width('100%')
    .padding({ left: 4, top: Theme.smallGap, bottom: Theme.tinyGap })
  }

  @Builder
  groupHeaderWithToggle(title: string, level: ExpiryLevel, count: number) {
    Row() {
      Row({ space: Theme.smallGap }) {
        this.geoShape(level)
        Text(title)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .letterSpacing(0.5)
        Text(`${count}项`)
          .fontSize(Theme.textCaption)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textTertiary)
      }
      .layoutWeight(1)

      Text(this.safeCollapsed ? '展开' : '收起')
        .fontSize(Theme.textSmall)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.safe)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .border({ width: 2, color: Theme.safe })
        .onClick(() => {
          this.safeCollapsed = !this.safeCollapsed;
        })
    }
    .width('100%')
    .padding({ left: 4, top: Theme.smallGap, bottom: Theme.tinyGap })
  }

  /* ============================================================
   * 几何状态形状：过期=红圆 / 临期=橙三角 / 安全=蓝绿方
   * ============================================================ */
  @Builder
  geoShape(level: ExpiryLevel) {
    if (level === ExpiryLevel.EXPIRED) {
      Circle({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.expired)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else if (level === ExpiryLevel.NEAR) {
      // 等腰三角形：用 Polygon 或三个点路径
      Canvas() {
        Path()
          .commands(`M ${Theme.geoSize / 2} 0 L ${Theme.geoSize} ${Theme.geoSize} L 0 ${Theme.geoSize} Z`)
          .fill(Theme.near)
          .stroke(Theme.ink)
          .strokeWidth(2)
      }
      .width(Theme.geoSize)
      .height(Theme.geoSize)
    } else {
      // 正方形
      Rect({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.safe)
        .stroke(Theme.ink)
        .strokeWidth(2)
    }
  }

  /* ============================================================
   * 图标按钮：白底黑边，零圆角，4x4 硬阴影
   * ============================================================ */
  @Builder
  iconButton(symbol: Resource, onClick: () => void) {
    Stack() {
      // 阴影层（黑色偏移）
      Column()
        .width(Theme.iconBtnSize)
        .height(Theme.iconBtnSize)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      // 主层
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
    .width(Theme.iconBtnSize + Theme.hardShadowOffset)
    .height(Theme.iconBtnSize + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(onClick)
  }

  /* ============================================================
   * 过期物资卡片：红底白字 + 黑边 + 硬阴影
   * ============================================================ */
  @Builder
  expiredCard(m: Material) {
    const left = remainingDays(m);
    const iconInfo = getCategoryIcon(m.category);

    Stack() {
      // 阴影层
      Column()
        .width('100%')
        .height(72)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      // 主层：红底白字
      Row() {
        Column() {
          SymbolGlyph(iconInfo.symbol)
            .fontSize(22)
            .fontColor([Theme.textWhite])
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .border({ width: 2, color: Theme.textWhite })
        .margin({ right: Theme.elementGap })

        Column({ space: Theme.tinyGap }) {
          Text(m.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${m.category} · ${m.quantity}${m.unit} · ${m.expiryDate}`)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textWhiteDim)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text(`-${-left}天`)
            .fontSize(Theme.textHeadline)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
          Text('已过期')
            .fontSize(Theme.textTiny)
            .fontColor(Theme.textWhiteDim)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.expired)
      .border(Theme.borderThin)
    }
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(() => {
      router.pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
    })
  }

  /* ============================================================
   * 临期 / 安全物资卡片：白底黑边硬阴影 + 左侧几何标识
   * ============================================================ */
  @Builder
  materialCard(m: Material) {
    const lv: ExpiryLevel = levelOf(m);
    const left = remainingDays(m);
    const iconInfo = getCategoryIcon(m.category);

    Stack() {
      // 阴影层
      Column()
        .width('100%')
        .height(72)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      // 主层
      Row() {
        this.geoShape(lv)
          .margin({ right: Theme.elementGap })

        Column() {
          SymbolGlyph(iconInfo.symbol)
            .fontSize(20)
            .fontColor([Theme.ink])
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .border({ width: 2, color: Theme.ink })
        .backgroundColor(iconInfo.bgColor)
        .margin({ right: Theme.elementGap })

        Column({ space: Theme.tinyGap }) {
          Text(m.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${m.category} · ${m.quantity}${m.unit}`)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text(lv === ExpiryLevel.NEAR ? `${left}天` : `${left}天`)
            .fontSize(Theme.textHeadline)
            .fontWeight(FontWeight.Bold)
            .fontColor(lv === ExpiryLevel.NEAR ? Theme.near : Theme.safe)
          Text(m.expiryDate)
            .fontSize(Theme.textTiny)
            .fontColor(Theme.textTertiary)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
    }
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(() => {
      router.pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
    })
  }

  /* ============================================================
   * FAB：深黄底 + 白 + 号 + 黑边 + 硬阴影
   * ============================================================ */
  @Builder
  hardShadowFab(onClick: () => void) {
    Stack() {
      Column()
        .width(Theme.fabSize)
        .height(Theme.fabSize)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Column() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(28)
          .fontColor([Theme.textWhite])
          .fontWeight(FontWeight.Bold)
      }
      .width(Theme.fabSize)
      .height(Theme.fabSize)
      .backgroundColor(Theme.yellowDark)
      .border(Theme.borderThin)
      .justifyContent(FlexAlign.Center)
    }
    .width(Theme.fabSize + Theme.hardShadowOffset)
    .height(Theme.fabSize + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .margin({ right: Theme.pagePadding, bottom: Theme.pagePadding })
    .onClick(onClick)
  }

  /* ============================================================
   * 空状态
   * ============================================================ */
  @Builder
  emptyState() {
    Column({ space: Theme.elementGap }) {
      // 包豪斯几何组合：红圆 + 橙三角 + 蓝绿方
      Row({ space: Theme.cardPadding }) {
        Circle({ width: 40, height: 40 })
          .fill(Theme.expired)
          .stroke(Theme.ink)
          .strokeWidth(2)

        Canvas() {
          Path()
            .commands(`M 20 0 L 40 40 L 0 40 Z`)
            .fill(Theme.near)
            .stroke(Theme.ink)
            .strokeWidth(2)
        }
        .width(40)
        .height(40)

        Rect({ width: 40, height: 40 })
          .fill(Theme.safe)
          .stroke(Theme.ink)
          .strokeWidth(2)
      }
      .margin({ bottom: Theme.smallGap })

      Text('还没有物资')
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
      Text('点击右下角 + 按钮，添加第一件物资吧')
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textTertiary)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /* ============================================================
   * 提醒设置底部 Sheet
   * ============================================================ */
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

      // 开关卡片
      Stack() {
        Column()
          .width('100%')
          .backgroundColor(Theme.ink)
          .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
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
              await this.saveReminderSettings();
            })
        }
        .width('100%')
        .padding(Theme.cardPadding)
        .backgroundColor(Theme.cardBg)
        .border(Theme.borderThin)
      }
      .width('100%')
      .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })

      if (this.reminderEnabled) {
        // 时间选择卡片
        Stack() {
          Column()
            .width('100%')
            .backgroundColor(Theme.ink)
            .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
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
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.yellowDark)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([Theme.textTertiary])
            }
            .padding({ left: 12, right: 10, top: 8, bottom: 8 })
            .border(Theme.borderThin)
            .backgroundColor(Theme.cardBg)
            .onClick(() => {
              this.pickReminderTime();
            })
          }
          .width('100%')
          .padding(Theme.cardPadding)
          .backgroundColor(Theme.cardBg)
          .border(Theme.borderThin)
        }
        .width('100%')
        .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
      }

      // 完成按钮：深黄主按钮
      Stack() {
        Column()
          .width('100%')
          .height(44)
          .backgroundColor(Theme.ink)
          .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
        Row() {
          Text('完成')
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
        }
        .width('100%')
        .height(44)
        .backgroundColor(Theme.yellowDark)
        .border(Theme.borderThin)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showSettingsDialog = false;
        })
      }
      .width('100%')
      .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
      .margin({ top: 8 })

      Column().width('100%').height(8)
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
