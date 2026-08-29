/**
 * 物资详情页：信息展示 + 编辑入口 + 删除 —— 包豪斯（Bauhaus）风格。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, ExpiryLevel, MaterialStatus } from '../model/Material';
import { CustomField, readCustomFieldValue } from '../model/CustomField';
import { MaterialDb } from '../db/MaterialDb';
import { levelOf, levelColor, levelText, remainingDays, remainingText } from '../service/ExpiryService';
import { ReminderService } from '../service/ReminderService';
import { UsageService } from '../service/UsageService';
import { Theme } from '../common/Theme';
import { HardShadowBox, HardShadowCard } from '../common/HardShadow';
import { getCategoryIcon } from '../common/CategoryIcons';

interface RouteParams {
  id?: number;
}

@Entry
@Component
struct ItemDetail {
  @StorageProp('avoidTopVp') avoidTopVp: number = 0;
  @StorageProp('avoidBottomVp') avoidBottomVp: number = 0;
  @State m: Material | undefined = undefined;
  @State customFieldsDefs: CustomField[] = [];
  @State loading: boolean = true;
  @State updatingStatus: boolean = false;
  private db: MaterialDb = MaterialDb.getInstance();
  private itemId: number = -1;

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error(`show toast failed: ${(e as BusinessError).message}`);
    }
  }

  onPageShow(): void {
    if (this.itemId < 0) {
      const params = this.getUIContext().getRouter().getParams() as RouteParams;
      if (params && params.id !== undefined) {
        this.itemId = params.id;
      }
    }
    if (this.itemId >= 0) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.db.init(ctx)
        .then(() => {
          return this.db.listCustomFields();
        })
        .then((defs: CustomField[]) => {
          this.customFieldsDefs = defs;
          return this.db.getById(this.itemId);
        })
        .then((m?: Material) => {
          this.m = m;
          this.loading = false;
        })
        .catch((e: BusinessError) => {
          console.error(`load material failed: ${e.message}`);
          this.loading = false;
        });
    } else {
      this.loading = false;
    }
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除物资',
      message: `确定删除「${this.m?.name}」吗？删除后将进入回收站，可在设置中恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.danger,
        action: () => {
          this.doDelete();
        }
      }
    });
  }

  private async doDelete(): Promise<void> {
    try {
      await this.db.remove(this.itemId);
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      try {
        await ReminderService.getInstance().syncDailyReminder(ctx);
      } catch (e) {
        console.error(`sync reminder failed: ${(e as BusinessError).message}`);
      }
      this.toast('已移入回收站');
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error(`delete failed: ${(e as BusinessError).message}`);
    }
  }

  /** 标记生命周期状态（开封/用完/丢弃/恢复在库），更新后刷新视图 */
  private async applyStatus(status: string, toastMsg: string, handledType?: string): Promise<void> {
    if (this.updatingStatus || this.itemId < 0) {
      return;
    }
    this.updatingStatus = true;
    try {
      await this.db.updateStatus(this.itemId, status, handledType);
      UsageService.getInstance().init(this.getUIContext().getHostContext() as common.UIAbilityContext);
      UsageService.getInstance().logStatusChanged(this.m?.name ?? '', status);
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      try {
        await ReminderService.getInstance().syncDailyReminder(ctx);
      } catch (e) {
        console.error(`sync reminder failed: ${(e as BusinessError).message}`);
      }
      this.toast(toastMsg);
      const fresh: Material | undefined = await this.db.getById(this.itemId);
      this.m = fresh;
    } catch (e) {
      console.error(`update status failed: ${(e as BusinessError).message}`);
      this.toast('操作失败，请重试');
    } finally {
      this.updatingStatus = false;
    }
  }

  /** 当前持久化状态是否终态（用完/丢弃） */
  private isTerminal(): boolean {
    const persisted: string = this.m?.status ?? MaterialStatus.ACTIVE;
    return persisted === MaterialStatus.EMPTY || persisted === MaterialStatus.DISCARDED;
  }

  build() {
    Column() {
      // 顶部导航：返回按钮（白底黑边40x40 + 硬阴影） + 标题
      Row() {
        this.backButton()

        Text('物资详情')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.elementGap })

        Blank()
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding,
        right: Theme.pagePadding,
        top: 16,
        bottom: 16
      })

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(Theme.ink)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.m) {
        Scroll() {
          Column({ space: Theme.cardGap }) {
            this.statusBanner()
            this.infoCard()
            this.statusActions()
          }
          .width('100%')
          .padding({
            left: Theme.pagePadding,
            right: Theme.pagePadding,
            top: 4,
            bottom: 24
          })
        }
        .layoutWeight(1)
        // 内容不足一屏时靠顶对齐（Scroll 通用 align 默认 Center 会把短内容垂直居中）
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)

        // 底部固定按钮：编辑 + 删除
        this.bottomBar()
      } else {
        Column() {
          Text('物资不存在或已删除')
            .fontSize(Theme.textBody)
            .fontColor(Theme.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.avoidTopVp, bottom: this.avoidBottomVp })
    .backgroundColor(Theme.pageBg)
  }

  @Builder
  backButton() {
    HardShadowBox({boxWidth: Theme.iconBtnSize, boxHeight: Theme.iconBtnSize, topStart: true}) {

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([Theme.textPrimary])
      }
      .backgroundColor(Theme.cardBg)
      .width(Theme.iconBtnSize)
      .height(Theme.iconBtnSize)
      .borderRadius(Theme.iconBtnRadius)
      .border(Theme.borderThin)
      .onClick(() => {
        this.getUIContext().getRouter().back();
      })
    }
  }

  @Builder
  statusBanner() {
    HardShadowCard({shadowMode: 0, topStart: true}) {

      Column({ space: Theme.smallGap }) {
        Row() {
          this.geoShape(levelOf(this.m!))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Text(this.bannerHeadline())
          .fontSize(Theme.statNumber)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textWhite)
          .margin({ top: Theme.smallGap })

        Text(this.bannerSubtitle())
          .fontSize(Theme.textBody)
          .fontColor(Theme.textWhite)
          .opacity(0.95)
      }
      .width('100%')
      .padding({
        left: Theme.cardPadding,
        right: Theme.cardPadding,
        top: 28,
        bottom: 28
      })
      .borderRadius(Theme.cardRadius)
      .border(Theme.borderThin)
      .backgroundColor(this.bannerColor())
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 终态时 Banner 主文案切换为处理结果 */
  private bannerHeadline(): string {
    if (this.m!.status === MaterialStatus.EMPTY) {
      return '已用完';
    }
    if (this.m!.status === MaterialStatus.DISCARDED) {
      return '已丢弃';
    }
    return levelText(levelOf(this.m!), remainingDays(this.m!));
  }

  private bannerSubtitle(): string {
    if (this.isTerminal()) {
      return this.m!.handledAt ? `处理于 ${this.m!.handledAt}` : `${this.m!.expiryDate} 到期`;
    }
    return `${this.m!.expiryDate} 到期`;
  }

  private bannerColor(): string {
    if (this.isTerminal()) {
      return Theme.textSecondary;
    }
    return levelColor(levelOf(this.m!));
  }

  /* ============================================================
   * 生命周期状态操作区：开封 / 用完 / 丢弃（终态可恢复在库）
   * ============================================================ */
  @Builder
  statusActions() {
    HardShadowCard({shadowMode: 0, topStart: true}) {

      Column({ space: Theme.elementGap }) {
        Row({ space: Theme.tinyGap }) {
          Text('生命周期')
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary)
        }
        .width('100%')

        if (!this.isTerminal()) {
          Row({ space: Theme.smallGap }) {
            this.statusActionChip('开封', MaterialStatus.OPENED, undefined, Theme.near)
            this.statusActionChip('用完', MaterialStatus.EMPTY, MaterialStatus.EMPTY, Theme.safe)
            this.statusActionChip('丢弃', MaterialStatus.DISCARDED, MaterialStatus.DISCARDED, Theme.danger)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

          if (this.m!.status === MaterialStatus.OPENED) {
            this.statusActionChip('恢复为未开封', MaterialStatus.ACTIVE, undefined, Theme.textSecondary)
          }
        } else {
          Row({ space: Theme.smallGap }) {
            Text(this.m!.status === MaterialStatus.DISCARDED ? '已丢弃' : '已用完')
              .fontSize(Theme.textSmall)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textWhite)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(Theme.textSecondary)
              .border(Theme.borderThin)
            Text('重新放回在库')
              .fontSize(Theme.textSmall)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.yellowDark)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
              .onClick(() => {
                this.applyStatus(MaterialStatus.ACTIVE, '已恢复为在库');
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
        }
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 状态操作小按钮：白底彩字黑边（非当前状态才可点） */
  @Builder
  statusActionChip(label: string, status: string, handledType: string | undefined, color: string) {
    Text(label)
      .fontSize(Theme.textSmall)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.m!.status === status ? Theme.textTertiary : color)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .opacity(this.m!.status === status ? 0.5 : 1)
      .onClick(() => {
        if (this.m!.status === status) {
          return;
        }
        const toast: string = label === '开封' ? '已标记为已开封'
          : label === '用完' ? '已标记为已用完'
            : label === '丢弃' ? '已标记为已丢弃'
              : '已恢复为未开封';
        this.applyStatus(status, toast, handledType);
      })
  }

  @Builder
  geoShape(lv: ExpiryLevel) {
    if (lv === ExpiryLevel.EXPIRED) {
      Circle({ width: 56, height: 56 })
        .fill(Theme.expired)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else if (lv === ExpiryLevel.NEAR) {
      Canvas() {
        Path()
          .commands(`M 28 0 L 56 56 L 0 56 Z`)
          .fill(Theme.near)
          .stroke(Theme.ink)
          .strokeWidth(2)
      }
      .width(56)
      .height(56)
    } else {
      Rect({ width: 56, height: 56 })
        .fill(Theme.safe)
        .stroke(Theme.ink)
        .strokeWidth(2)
    }
  }

  @Builder
  infoCard() {
    HardShadowCard({shadowMode: 0, topStart: true}) {

      Column({ space: 0 }) {
        // 头部：分类图标方块（2vp黑边） + 名称 + 分类/数量
        Row({ space: Theme.elementGap }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph(getCategoryIcon(this.m!.category).symbol)
              .fontSize(24)
              .fontColor([Theme.textPrimary])
          }
          .width(52)
          .height(52)
          .backgroundColor(Theme.cardBg)
          .border(Theme.borderThin)

          Column({ space: Theme.tinyGap }) {
            Text(this.m!.name)
              .fontSize(Theme.textTitle)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.m!.location && this.m!.location.length > 0
              ? `${this.m!.category} · ${this.m!.location} · ${this.m!.quantity} ${this.m!.unit}`
              : `${this.m!.category} · ${this.m!.quantity} ${this.m!.unit}`)
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ bottom: Theme.cardPadding })

        Divider().color(Theme.divider).strokeWidth(1)

        this.infoRow('生产日期', this.m!.productionDate)
        this.infoRow('保质期', this.shelfLifeText())
        this.infoRow('到期日期', this.m!.expiryDate)
        this.infoRow('距到期', remainingText(this.m!))

        if (this.m!.barcode && this.m!.barcode.trim().length > 0) {
          Divider().color(Theme.divider).strokeWidth(1)
          this.infoRow('条形码', this.m!.barcode)
        }

        ForEach(this.customFieldsDefs, (def: CustomField) => {
          if (this.hasCustomFieldValue(def.id)) {
            Divider().color(Theme.divider).strokeWidth(1)
            this.infoRow(def.name, this.getCustomFieldValue(def.id))
          }
        }, (def: CustomField) => def.id)

        if (this.m!.note !== '') {
          Divider().color(Theme.divider).strokeWidth(1)
          Column({ space: Theme.tinyGap }) {
            Text('备注')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textSecondary)
            Text(this.m!.note)
              .fontSize(Theme.textBody)
              .fontColor(Theme.textPrimary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 12, bottom: 12 })
        }

        Divider().color(Theme.divider).strokeWidth(1)
        this.infoRow('创建于', this.m!.createdAt)
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .borderRadius(Theme.cardRadius)
      .border(Theme.borderThin)
      .backgroundColor(Theme.cardBg)
      .alignItems(HorizontalAlign.Start)
    }
  }

  private hasCustomFieldValue(fieldId: string): boolean {
    if (!this.m) {
      return false;
    }
    return readCustomFieldValue(this.m.customFields, fieldId).trim().length > 0;
  }

  /** 保质期显示：月数优先展示（保留原始录入口径） */
  private shelfLifeText(): string {
    if (this.m!.shelfLifeMonths !== undefined && this.m!.shelfLifeMonths !== null && this.m!.shelfLifeMonths > 0) {
      return `${this.m!.shelfLifeMonths} 个月`;
    }
    return `${this.m!.shelfLifeDays} 天`;
  }

  private getCustomFieldValue(fieldId: string): string {
    if (!this.m) {
      return '';
    }
    return readCustomFieldValue(this.m.customFields, fieldId);
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textSecondary)
      Blank()
      Text(value)
        .fontSize(Theme.textSubhead)
        .fontColor(Theme.textPrimary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  bottomBar() {
    Row({ space: Theme.elementGap }) {
      // 编辑：深黄底白字 + 黑边 + 硬阴影
      this.primaryBtn('编辑', Theme.yellowDark, Theme.textWhite, () => {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/AddItem', params: { id: this.itemId } });
      })

      // 删除：白底红字 + 黑边 + 硬阴影
      this.primaryBtn('删除', Theme.cardBg, Theme.danger, () => {
        this.confirmDelete();
      })
    }
    .width('100%')
    .padding({
      left: Theme.pagePadding,
      right: Theme.pagePadding,
      top: 12,
      bottom: 20
    })
  }

  @Builder
  primaryBtn(text: string, bg: string, fg: string, action: () => void) {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.ink)
      .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Button(text, { type: ButtonType.Normal, stateEffect: true })
        .width('100%')
        .height(Theme.primaryBtnHeight)
        .backgroundColor(bg)
        .fontColor(fg)
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Bold)
        .borderRadius(Theme.buttonRadius)
        .border(Theme.borderThin)
        .onClick(() => {
          action();
        })
    }
    .layoutWeight(1)
    .height(Theme.primaryBtnHeight + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
  }
}
