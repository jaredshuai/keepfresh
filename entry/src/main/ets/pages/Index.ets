/**
 * 首页：包豪斯风格 —— 变体 C 状态分组布局（已过期 / 临期 / 安全折叠）
 * 几何状态语言：过期=红色圆形，临期=橙色三角形，安全=蓝绿正方形
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, ExpiryLevel, MaterialStatus, DerivedStatus, DEFAULT_CATEGORIES } from '../model/Material';
import { MaterialDb } from '../db/MaterialDb';
import {
  ExpiryStats,
  levelOf,
  levelColor,
  remainingDays,
  sortByExpirationAsc,
  statsOf,
  getActualStatus
} from '../service/ExpiryService';
import { ensureNotificationEnabled, publishExpiryAlert, requestNotificationEnable } from '../service/NotificationService';
import { ReminderService, ReminderSettings } from '../service/ReminderService';
import { SettingsService } from '../service/SettingsService';
import { Theme } from '../common/Theme';
import { getCategoryIcon } from '../common/CategoryIcons';
import { filterByKeyword } from '../common/SearchFilter';

interface TimePickerResult {
  hour?: number;
  minute?: number;
}

interface GroupedMaterials {
  expired: Material[];
  near: Material[];
  safe: Material[];
  handled: Material[];
}

/** 状态 Tab 定义（骨架来自 the-ai-menu PantryView 状态筛选） */
interface StatusTab {
  id: string;     // 'all' | 'active' | 'opened' | 'expiring' | 'expired'
  label: string;
}

const STATUS_TABS: StatusTab[] = [
  { id: 'all', label: '全部' },
  { id: 'active', label: '在库' },
  { id: 'opened', label: '已开封' },
  { id: 'expiring', label: '临期' },
  { id: 'expired', label: '已过期' }
];

/** 每次启动只发一条汇总通知 */
let notifiedThisSession: boolean = false;

@Entry
@Component
struct Index {
  @State materials: Material[] = [];
  @State stats: ExpiryStats = { total: 0, expired: 0, near: 0, safe: 0 };
  @State groupedMaterials: GroupedMaterials = { expired: [], near: [], safe: [], handled: [] };
  @State loading: boolean = true;
  @State showSettingsDialog: boolean = false;
  @State reminderEnabled: boolean = true;
  @State reminderHour: number = 9;
  @State reminderMinute: number = 0;
  @State safeCollapsed: boolean = true;   // 安全组默认折叠
  @State handledCollapsed: boolean = true; // 已处理组默认折叠
  // ── 筛选状态（骨架来自 the-ai-menu：关键词 + 状态 Tab + 分类 Chip）──
  @State searchKeyword: string = '';
  @State activeStatusTab: string = 'all';
  @State selectedCategory: string = '';   // 空 = 全部分类
  @State categories: string[] = DEFAULT_CATEGORIES.slice();
  private db: MaterialDb = MaterialDb.getInstance();

  onPageShow(): void {
    // 通知跳转：EntryAbility 已把 want.parameters.filterLevel 存入 AppStorage，
    // 这里消费掉——切到对应状态 Tab，让用户点通知直达过期/临期列表
    const targetFilter = AppStorage.get<string>('targetFilterLevel');
    if (targetFilter === 'expired' || targetFilter === 'expiring') {
      this.activeStatusTab = targetFilter;
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
    try {
      await ReminderService.getInstance().init(ctx);
      const settings: ReminderSettings = {
        enabled: this.reminderEnabled,
        hour: this.reminderHour,
        minute: this.reminderMinute
      };
      await ReminderService.getInstance().updateSettings(settings);
      await ReminderService.getInstance().syncDailyReminder(ctx);
      this.getUIContext().getPromptAction().showToast({ message: '已更新提醒设置' });
    } catch (e) {
      console.error(`save reminder settings failed: ${(e as BusinessError).message}`);
    }
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
      // 分类列表：管理页自定义定义（按排序）→ 预设 → 数据中出现过的
      this.categories = await this.db.listEffectiveNames('category', DEFAULT_CATEGORIES);
      this.applyFilters();
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

  /** 筛选链路（移植自 the-ai-menu applyPantryListControls）：关键词 → 分类 → 状态 Tab → 分组排序 */
  private applyFilters(): void {
    let filtered: Material[] = this.materials;
    filtered = filterByKeyword(filtered, this.searchKeyword);
    if (this.selectedCategory.length > 0) {
      filtered = filtered.filter((m: Material): boolean => m.category === this.selectedCategory);
    }
    if (this.activeStatusTab !== 'all') {
      filtered = filtered.filter((m: Material): boolean => getActualStatus(m) === this.activeStatusTab);
    }
    this.groupedMaterials = this.groupByStatus(filtered);
  }

  /** 状态机分组：过期 → 临期 → 安全（在库+开封）→ 已处理（终态沉底） */
  private groupByStatus(list: Material[]): GroupedMaterials {
    const expired: Material[] = [];
    const near: Material[] = [];
    const safe: Material[] = [];
    const handled: Material[] = [];
    for (let i = 0; i < list.length; i++) {
      const m = list[i];
      const actual = getActualStatus(m);
      if (actual === DerivedStatus.EXPIRED) expired.push(m);
      else if (actual === DerivedStatus.EXPIRING) near.push(m);
      else if (actual === MaterialStatus.EMPTY || actual === MaterialStatus.DISCARDED) handled.push(m);
      else safe.push(m);
    }
    // 组内按到期日升序（无到期日靠后）——接线 ExpiryService.sortByExpirationAsc
    const result: GroupedMaterials = {
      expired: sortByExpirationAsc(expired),
      near: sortByExpirationAsc(near),
      safe: sortByExpirationAsc(safe),
      handled: sortByExpirationAsc(handled)
    };
    return result;
  }

  /** 当前筛选结果总数（空态判断用） */
  private filteredTotal(): number {
    const g = this.groupedMaterials;
    return g.expired.length + g.near.length + g.safe.length + g.handled.length;
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
              // ── 筛选区：搜索框 + 状态 Tab + 分类 Chip（骨架来自 the-ai-menu）──
              this.searchBar()
              this.statusTabs()
              this.categoryChips()

              if (this.filteredTotal() === 0) {
                this.noResultState()
              } else {
                // ─── 已过期组（红色圆形） ───
                if (this.groupedMaterials.expired.length > 0) {
                  this.groupHeader('已过期', ExpiryLevel.EXPIRED, this.groupedMaterials.expired.length)
                  Column({ space: Theme.smallGap }) {
                    ForEach(this.groupedMaterials.expired, (m: Material) => {
                      this.expiredCard(m)
                    }, (m: Material) => m.id.toString())
                  }
                  .width('100%')
                }

                // ─── 临期组（橙色三角形） ───
                if (this.groupedMaterials.near.length > 0) {
                  this.groupHeader('临期', ExpiryLevel.NEAR, this.groupedMaterials.near.length)
                  Column({ space: Theme.smallGap }) {
                    ForEach(this.groupedMaterials.near, (m: Material) => {
                      this.materialCard(m)
                    }, (m: Material) => m.id.toString())
                  }
                  .width('100%')
                }

                // ─── 安全组（蓝绿正方形，可折叠） ───
                if (this.groupedMaterials.safe.length > 0) {
                  this.groupHeaderWithToggle('安全', ExpiryLevel.SAFE, this.groupedMaterials.safe.length)
                  if (!this.safeCollapsed) {
                    Column({ space: Theme.smallGap }) {
                      ForEach(this.groupedMaterials.safe, (m: Material) => {
                        this.materialCard(m)
                      }, (m: Material) => m.id.toString())
                    }
                    .width('100%')
                  }
                }

                // ─── 已处理组（用完/丢弃，可折叠，沉底） ───
                if (this.groupedMaterials.handled.length > 0) {
                  this.handledGroupHeader(this.groupedMaterials.handled.length)
                  if (!this.handledCollapsed) {
                    Column({ space: Theme.smallGap }) {
                      ForEach(this.groupedMaterials.handled, (m: Material) => {
                        this.handledCard(m)
                      }, (m: Material) => m.id.toString())
                    }
                    .width('100%')
                  }
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
        this.getUIContext().getRouter().pushUrl({ url: 'pages/AddItem' });
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
          () => this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' })
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
   * 搜索框（骨架来自 the-ai-menu：白底黑边硬阴影 + 放大镜）
   * ============================================================ */
  @Builder
  searchBar() {
    Stack() {
      Column()
        .width('100%')
        .height(40)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Row({ space: Theme.smallGap }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([Theme.textTertiary])
        TextInput({ text: this.searchKeyword, placeholder: '搜索物资 / 分类 / 位置 / 备注' })
          .fontSize(Theme.textBody)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textTertiary)
          .placeholderFont({ size: Theme.textCaption })
          .backgroundColor(Theme.inputBg)
          .layoutWeight(1)
          .padding({ left: 0, right: 0 })
          .height(36)
          .onChange((v: string) => {
            this.searchKeyword = v;
            this.applyFilters();
          })
        if (this.searchKeyword.length > 0) {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(16)
            .fontColor([Theme.textTertiary])
            .onClick(() => {
              this.searchKeyword = '';
              this.applyFilters();
            })
        }
      }
      .width('100%')
      .padding({ left: Theme.elementGap, right: Theme.elementGap })
      .height(40)
      .backgroundColor(Theme.inputBg)
      .border(Theme.borderThin)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
  }

  /* ============================================================
   * 状态 Tab（全部/在库/已开封/临期/已过期）：Chip 单选行
   * ============================================================ */
  @Builder
  statusTabs() {
    Scroll() {
      Row({ space: Theme.smallGap }) {
        ForEach(STATUS_TABS, (tab: StatusTab) => {
          Stack() {
            Column()
              .height(28)
              .backgroundColor(Theme.ink)
              .margin({ left: 3, top: 3 })

            Text(tab.label)
              .fontSize(Theme.textSmall)
              .fontWeight(this.activeStatusTab === tab.id ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.activeStatusTab === tab.id ? Theme.textWhite : Theme.textPrimary)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .backgroundColor(this.activeStatusTab === tab.id ? Theme.yellowDark : Theme.cardBg)
              .border(Theme.borderThin)
              .onClick(() => {
                this.activeStatusTab = tab.id;
                this.applyFilters();
              })
          }
          .padding({ right: 3, bottom: 3 })
        }, (tab: StatusTab) => tab.id)
      }
      .padding({ top: Theme.tinyGap, bottom: Theme.tinyGap })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  /* ============================================================
   * 分类 Chip 筛选行（全部 + 各分类，单选）
   * ============================================================ */
  @Builder
  categoryChips() {
    Scroll() {
      Row({ space: Theme.smallGap }) {
        Stack() {
          Column()
            .height(28)
            .backgroundColor(Theme.ink)
            .margin({ left: 3, top: 3 })

          Text('全部')
            .fontSize(Theme.textSmall)
            .fontWeight(this.selectedCategory.length === 0 ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.selectedCategory.length === 0 ? Theme.textWhite : Theme.textPrimary)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .backgroundColor(this.selectedCategory.length === 0 ? Theme.yellowDark : Theme.cardBg)
            .border(Theme.borderThin)
            .onClick(() => {
              this.selectedCategory = '';
              this.applyFilters();
            })
        }
        .padding({ right: 3, bottom: 3 })

        ForEach(this.categories, (cat: string) => {
          Stack() {
            Column()
              .height(28)
              .backgroundColor(Theme.ink)
              .margin({ left: 3, top: 3 })

            Text(cat)
              .fontSize(Theme.textSmall)
              .fontWeight(this.selectedCategory === cat ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.selectedCategory === cat ? Theme.textWhite : Theme.textPrimary)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .backgroundColor(this.selectedCategory === cat ? Theme.yellowDark : Theme.cardBg)
              .border(Theme.borderThin)
              .onClick(() => {
                this.selectedCategory = cat;
                this.applyFilters();
              })
          }
          .padding({ right: 3, bottom: 3 })
        }, (cat: string) => cat)
      }
      .padding({ top: Theme.tinyGap, bottom: Theme.tinyGap })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  /* ============================================================
   * 筛选无结果空态
   * ============================================================ */
  @Builder
  noResultState() {
    Column({ space: Theme.smallGap }) {
      Text('没有符合条件的物资')
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
      Text('试试更换关键词或筛选条件')
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textTertiary)
    }
    .width('100%')
    .padding({ top: Theme.cardGap, bottom: Theme.cardGap })
    .justifyContent(FlexAlign.Center)
  }

  /* ============================================================
   * 已处理组 header（已用完/已丢弃，黑灰几何，可折叠）
   * ============================================================ */
  @Builder
  handledGroupHeader(count: number) {
    Row() {
      Row({ space: Theme.smallGap }) {
        // 已处理：黑边白底方框（非几何三色）
        Rect({ width: Theme.geoSize, height: Theme.geoSize })
          .fill(Theme.cardBg)
          .stroke(Theme.ink)
          .strokeWidth(2)
        Text('已处理')
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textSecondary)
          .letterSpacing(0.5)
        Text(`${count}项`)
          .fontSize(Theme.textCaption)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textTertiary)
      }
      .layoutWeight(1)

      Text(this.handledCollapsed ? '展开' : '收起')
        .fontSize(Theme.textSmall)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .border({ width: 2, color: Theme.textSecondary })
        .onClick(() => {
          this.handledCollapsed = !this.handledCollapsed;
        })
    }
    .width('100%')
    .padding({ left: 4, top: Theme.smallGap, bottom: Theme.tinyGap })
  }

  /* ============================================================
   * 已处理物资卡片：白底黑边 + 状态标签（已用完/已丢弃）
   * ============================================================ */
  @Builder
  handledCard(m: Material) {
    Stack() {
      Column()
        .width('100%')
        .height(72)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Row() {
        Column() {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(20)
            .fontColor([Theme.textTertiary])
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .border({ width: 2, color: Theme.ink })
        .backgroundColor(Theme.cardBg)
        .margin({ right: Theme.elementGap })

        Column({ space: Theme.tinyGap }) {
          Text(m.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${m.category} · ${m.quantity}${m.unit}`)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(m.status === MaterialStatus.DISCARDED ? '已丢弃' : '已用完')
          .fontSize(Theme.textSmall)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textWhite)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.textSecondary)
          .border(Theme.borderThin)
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .opacity(0.7)
    }
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
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
          SymbolGlyph(getCategoryIcon(m.category).symbol)
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
          Text(`-${-remainingDays(m)}天`)
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
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
    })
  }

  /* ============================================================
   * 临期 / 安全物资卡片：白底黑边硬阴影 + 左侧几何标识
   * ============================================================ */
  @Builder
  materialCard(m: Material) {
    Stack() {
      // 阴影层
      Column()
        .width('100%')
        .height(72)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      // 主层
      Row() {
        Stack() {
          this.geoShape(levelOf(m))
        }
        .margin({ right: Theme.elementGap })

        Column() {
          SymbolGlyph(getCategoryIcon(m.category).symbol)
            .fontSize(20)
            .fontColor([Theme.ink])
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .border({ width: 2, color: Theme.ink })
        .backgroundColor(getCategoryIcon(m.category).bgColor)
        .margin({ right: Theme.elementGap })

        Column({ space: Theme.tinyGap }) {
          Text(m.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(m.location.length > 0
            ? `${m.category} · ${m.location} · ${m.quantity}${m.unit}`
            : `${m.category} · ${m.quantity}${m.unit}`)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text(`${remainingDays(m)}天`)
            .fontSize(Theme.textHeadline)
            .fontWeight(FontWeight.Bold)
            .fontColor(levelOf(m) === ExpiryLevel.NEAR ? Theme.near : Theme.safe)
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
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
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
