/**
 * 首页：包豪斯风格 —— 变体 C 状态分组布局（已过期 / 临期 / 安全折叠）
 * 几何状态语言：过期=红色圆形，临期=橙色三角形，安全=蓝绿正方形
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { Material, DEFAULT_CATEGORIES, materialCardKey } from '../model/Material';
import { MaterialDb } from '../db/MaterialDb';
import {
  ExpiryStats,
  statsOf
} from '../common/ExpiryService';
import { ensureNotificationEnabled, publishExpiryAlert, requestNotificationEnable } from '../service/NotificationService';
import { SettingsService } from '../service/SettingsService';
import { Theme } from '../common/Theme';
import { HardShadowBox, HardShadowCard } from '../common/HardShadow';
import { UsageService } from '../service/UsageService';
import { applyListFilters, groupByStatus, GroupedMaterials } from '../common/SearchFilter';
import { ReminderSettingsPanel } from '../components/ReminderSettingsPanel';
import { MaterialCard } from '../components/MaterialCard';


/**
 * 分组头组件（已过期/临期/安全/已处理 四组共用，C4 三胞胎合一）。
 * 独立组件而非 @Builder：计数/折叠态是父页面状态，@Prop 由父驱动响应式
 * （#builder-by-value：按值传参不随状态刷新，组计数会凝滞——c48823d 教训）。
 * 视觉沿旧例：非折叠组计数裸数字；折叠组计数带「项」+ 右侧开关
 * （安全组开关描边 safe 色、已处理组 textSecondary；已处理标题用次级色）。
 */
@Component
struct GroupHeader {
  @Prop shape: string = 'safe';   // 'expired' | 'near' | 'safe' | 'handled'
  @Prop title: string = '';
  @Prop count: number = 0;
  @Prop collapsible: boolean = false;
  @Prop collapsed: boolean = false;
  @Prop showToggle: boolean = true;  // 筛选态由父隐藏开关
  onToggle: () => void = () => {};

  build() {
    Row() {
      Row({ space: Theme.smallGap }) {
        this.shapeMark()
        Text(this.title)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.shape === 'handled' ? Theme.textSecondary : Theme.textPrimary)
          .letterSpacing(0.5)
        Text(this.collapsible ? `${this.count}项` : `${this.count}`)
          .fontSize(Theme.textCaption)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textTertiary)
      }
      .layoutWeight(1)

      if (this.collapsible && this.showToggle) {
        Text(this.collapsed ? '展开' : '收起')
          .fontSize(Theme.textSmall)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.shape === 'safe' ? Theme.safe : Theme.textSecondary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .border({ width: 2, color: this.shape === 'safe' ? Theme.safe : Theme.textSecondary })
          .onClick(() => {
            this.onToggle();
          })
      }
    }
    .width('100%')
    .padding({ left: 4, top: Theme.smallGap, bottom: Theme.tinyGap })
  }

  /** 组头形状标记：过期红圆/临期橙三角/安全蓝绿方/已处理黑边白底方（同 geoShape 惯例，原生组件） */
  @Builder
  shapeMark() {
    if (this.shape === 'expired') {
      Circle({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.expired)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else if (this.shape === 'near') {
      Polygon({ width: Theme.geoSize, height: Theme.geoSize })
        .points([[Theme.geoSize / 2, 0], [Theme.geoSize, Theme.geoSize], [0, Theme.geoSize]])
        .fill(Theme.near)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else if (this.shape === 'handled') {
      Rect({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.cardBg)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else {
      Rect({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.safe)
        .stroke(Theme.ink)
        .strokeWidth(2)
    }
  }
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
  @StorageProp('avoidTopVp') avoidTopVp: number = 0;
  @StorageProp('avoidBottomVp') avoidBottomVp: number = 0;
  // 详情页写库完成后自增此版本号，@Watch 立即重查——兜住「用户在 await 写完成前
  // 按返回，onPageShow 的 refresh 读到写提交前的旧状态」的跨页竞速（卡片凝滞）
  @StorageProp('materialsVersion') @Watch('onMaterialsVersionChange') materialsVersion: number = 0;
  /** 智感握姿：左手握持时 FAB 换到左下角；默认右手（右下角）。不支持的机型保持默认 */
  @State fabOnLeft: boolean = false;
  @State materials: Material[] = [];
  @State stats: ExpiryStats = { total: 0, expired: 0, near: 0, safe: 0 };
  @State groupedMaterials: GroupedMaterials = { expired: [], near: [], safe: [], handled: [] };
  @State loading: boolean = true;
  @State showSettingsDialog: boolean = false;
  @State safeCollapsed: boolean = true;   // 安全组默认折叠
  @State handledCollapsed: boolean = true; // 已处理组默认折叠
  // ── 筛选状态（骨架来自 the-ai-menu：关键词 + 状态 Tab + 分类 Chip）──
  @State searchKeyword: string = '';
  @State activeStatusTab: string = 'all';
  @State selectedCategory: string = '';   // 空 = 全部分类
  @State categories: string[] = DEFAULT_CATEGORIES.slice();
  private db: MaterialDb = MaterialDb.getInstance();
  private scroller: Scroller = new Scroller();

  private onHoldingHandChanged = (status: motion.HoldingHandStatus): void => {
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      this.fabOnLeft = true;
    } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      this.fabOnLeft = false;
    }
    // NOT_HELD / BOTH_HANDS_HELD / UNKNOWN_STATUS 是过渡态，FAB 保持原位
  };

  aboutToAppear(): void {
    // 智感握姿（HarmonyOS 6+ 部分机型）：on 必须 try/catch——未支持设备抛 801
    // 不捕获会直接崩溃；201 = 权限未声明。模拟器恒 801，走默认右侧。
    try {
      motion.on('holdingHandChanged', this.onHoldingHandChanged);
    } catch (e) {
      console.info(`holdingHandChanged unavailable: code=${(e as BusinessError).code}`);
    }
  }

  aboutToDisappear(): void {
    try {
      motion.off('holdingHandChanged', this.onHoldingHandChanged);
    } catch (e) {
      console.info(`holdingHandChanged off failed: code=${(e as BusinessError).code}`);
    }
  }

  onPageShow(): void {
    // 通知跳转：EntryAbility 已把 want.parameters.filterLevel 存入 AppStorage，
    // 这里消费掉——切到对应状态 Tab，让用户点通知直达过期/临期列表
    const targetFilter = AppStorage.get<string>('targetFilterLevel');
    if (targetFilter === 'expired' || targetFilter === 'expiring') {
      this.activeStatusTab = targetFilter;
      AppStorage.setOrCreate('targetFilterLevel', undefined);
    }

    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UsageService.getInstance().init(ctx);

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

  private openReminderSettingsDialog(): void {
    this.showSettingsDialog = true;
  }

  /** 卡片点击进详情（候选 4：三卡片合一后唯一跳转入口） */
  private openDetail(id: number): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ItemDetail', params: { id: id } });
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

  /** 物资数据版本变化（详情页状态写入完成）→ 立即重查首页 */
  onMaterialsVersionChange(): void {
    this.refresh();
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
        await publishExpiryAlert(this.materials);
      }
    } catch (e) {
      console.error(`load materials failed: ${(e as BusinessError).message}`);
    } finally {
      this.loading = false;
    }
  }

  /** 筛选链路（下沉 common/SearchFilter）：关键词 → 分类 → 状态 Tab → 分组排序 */
  private applyFilters(): void {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    const filtered: Material[] = applyListFilters(
      this.materials, this.searchKeyword, this.selectedCategory, this.activeStatusTab);
    this.groupedMaterials = groupByStatus(filtered);
  }

  /** 当前筛选结果总数（空态判断用） */
  /** 是否处于筛选态（非「全部」）：此时分组强制展开、折叠开关隐藏 */
  private isFiltering(): boolean {
    return this.activeStatusTab !== 'all' || this.selectedCategory.length > 0
      || this.searchKeyword.trim().length > 0;
  }

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
          // ── 固定筛选区：搜索框 + 状态 Tab + 分类 Chip —— 不随列表滚动，位置恒定 ──
          Column({ space: Theme.cardGap }) {
            this.searchBar()
            this.statusTabs()
            this.categoryChips()
          }
          .width('100%')
          .padding({
            left: Theme.pagePadding,
            right: Theme.pagePadding,
            top: Theme.smallGap
          })

          Scroll(this.scroller) {
            Column({ space: Theme.cardGap }) {
              if (this.filteredTotal() === 0) {
                this.noResultState()
              } else {
                // ─── 已过期组（红色圆形） ───
                if (this.groupedMaterials.expired.length > 0) {
                  GroupHeader({
                    shape: 'expired',
                    title: '已过期',
                    count: this.groupedMaterials.expired.length
                  })
                  Column({ space: Theme.smallGap }) {
                    ForEach(this.groupedMaterials.expired, (m: Material) => {
                      MaterialCard({ material: m, onOpen: () => this.openDetail(m.id) })
                    }, materialCardKey)
                  }
                  .width('100%')
                }

                // ─── 临期组（橙色三角形） ───
                if (this.groupedMaterials.near.length > 0) {
                  GroupHeader({
                    shape: 'near',
                    title: '临期',
                    count: this.groupedMaterials.near.length
                  })
                  Column({ space: Theme.smallGap }) {
                    ForEach(this.groupedMaterials.near, (m: Material) => {
                      MaterialCard({ material: m, onOpen: () => this.openDetail(m.id) })
                    }, materialCardKey)
                  }
                  .width('100%')
                }

                // ─── 安全组（蓝绿正方形，可折叠） ───
                if (this.groupedMaterials.safe.length > 0) {
                  GroupHeader({
                    shape: 'safe',
                    title: '安全',
                    count: this.groupedMaterials.safe.length,
                    collapsible: true,
                    collapsed: this.safeCollapsed,
                    showToggle: !this.isFiltering(),
                    onToggle: () => {
                      this.safeCollapsed = !this.safeCollapsed;
                    }
                  })
                  if (!this.safeCollapsed || this.isFiltering()) {
                    Column({ space: Theme.smallGap }) {
                        ForEach(this.groupedMaterials.safe, (m: Material) => {
                          MaterialCard({ material: m, onOpen: () => this.openDetail(m.id) })
                        }, materialCardKey)
                      }
                      .width('100%')
                  }
                }

                // ─── 已处理组（用完/丢弃，可折叠，沉底） ───
                if (this.groupedMaterials.handled.length > 0) {
                  GroupHeader({
                    shape: 'handled',
                    title: '已处理',
                    count: this.groupedMaterials.handled.length,
                    collapsible: true,
                    collapsed: this.handledCollapsed,
                    showToggle: !this.isFiltering(),
                    onToggle: () => {
                      this.handledCollapsed = !this.handledCollapsed;
                    }
                  })
                  if (!this.handledCollapsed || this.isFiltering()) {
                    Column({ space: Theme.smallGap }) {
                        ForEach(this.groupedMaterials.handled, (m: Material) => {
                          MaterialCard({ material: m, onOpen: () => this.openDetail(m.id) })
                        }, materialCardKey)
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
              right: Theme.pagePadding
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
    .padding({ top: this.avoidTopVp, bottom: this.avoidBottomVp })
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
    HardShadowCard({shadowMode: 40}) {

      Row({ space: Theme.smallGap }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([Theme.textTertiary])
        TextInput({ text: this.searchKeyword, placeholder: '搜索物资 / 分类 / 位置 / 备注' })
          .fontSize(Theme.textBody)
          .borderRadius(Theme.inputRadius)
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
  }

  /* ============================================================
   * 状态 Tab（全部/在库/已开封/临期/已过期）：Chip 单选行
   * ============================================================ */
  @Builder
  statusTabs() {
    // 换行铺开而非横滑：5 个 tab 全部可见，不留隐藏选项（Mobbin 调研：Beli/Deliveroo 同款）
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
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
        .margin({ right: Theme.smallGap, bottom: Theme.smallGap })
      }, (tab: StatusTab) => tab.id)
    }
    .padding({ top: Theme.tinyGap })
    .width('100%')
  }

  /* ============================================================
   * 分类 Chip 筛选行（全部 + 各分类，单选）
   * ============================================================ */
  @Builder
  categoryChips() {
    // 换行铺开而非横滑：分类全可见，自建分类不会被藏在滑动区外（Mobbin 调研：Beli/Deliveroo 同款）
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
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
      .margin({ right: Theme.smallGap, bottom: Theme.smallGap })

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
        .margin({ right: Theme.smallGap, bottom: Theme.smallGap })
      }, (cat: string) => cat)
    }
    .padding({ top: Theme.tinyGap })
    .width('100%')
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
   * 图标按钮：白底黑边，零圆角，4x4 硬阴影
   * ============================================================ */
  @Builder
  iconButton(symbol: Resource, onClick: () => void) {
    HardShadowBox({boxWidth: Theme.iconBtnSize, boxHeight: Theme.iconBtnSize, onBoxClick: onClick}) {

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
  }

  /* ============================================================
   * FAB：深黄底 + 白 + 号 + 黑边 + 硬阴影
   * ============================================================ */
  @Builder
  hardShadowFab(onClick: () => void) {
    // 全宽 Row 承载 + 动态对齐：智感握姿识别左手握持时 FAB 换左下角，右手（默认）右下角
    Row() {
      HardShadowBox({boxWidth: Theme.fabSize, boxHeight: Theme.fabSize, onBoxClick: onClick}) {

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
    }
    .width('100%')
    .justifyContent(this.fabOnLeft ? FlexAlign.Start : FlexAlign.End)
    // 底部安全边距：避免按钮+阴影怼死屏幕角落（手势条避让由根容器 padding 负责）
    .padding({ left: Theme.pagePadding, right: Theme.pagePadding, bottom: Theme.pagePadding })
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

        // 原生 Polygon：同 geoShape，Canvas+Path 在高分屏缩放失真
        Polygon({ width: 40, height: 40 })
          .points([[20, 0], [40, 40], [0, 40]])
          .fill(Theme.near)
          .stroke(Theme.ink)
          .strokeWidth(2)

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
   * 提醒设置底部 Sheet（候选 3：面板收拢为 components/ReminderSettingsPanel，
   * 与 Settings 页共用；本处只剩标题 + 面板 + 完成按钮）
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

      ReminderSettingsPanel()

      // 完成按钮：深黄主按钮
      HardShadowCard({shadowMode: 44}) {
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
