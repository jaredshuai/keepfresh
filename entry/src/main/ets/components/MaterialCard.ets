/**
 * 物资卡片（候选 4 深化）：过期红卡 / 临期・安全白卡 / 已处理灰卡三种渲染
 * 合一为单组件，变体由物资状态自行派生，调用方只传 material。
 *
 * 先例沿 GroupHeader（C4 组头三胞胎合一）：独立组件而非 @Builder——
 * @Builder 按值传参不随状态刷新（#builder-by-value）；ForEach 的 key
 * （materialCardKey，编入 status/updatedAt）在状态翻转时重建组件保证新鲜。
 *
 * 布局逐像素转录自 Index 原三个 @Builder（expiredCard/materialCard/handledCard）。
 */
import { Material, MaterialStatus, ExpiryLevel } from '../model/Material';
import { levelOf, remainingDays } from '../common/ExpiryService';
import { getCategoryIcon } from '../common/CategoryIcons';
import { Theme } from '../common/Theme';
import { HardShadowCard } from '../common/HardShadow';

@Component
export struct MaterialCard {
  material: Material = {} as Material;
  onOpen: () => void = () => {};

  /** 变体派生：终态 → 已处理灰卡；过期 → 红卡；其余（临期/安全/开封）→ 白卡 */
  private variant(): string {
    if (this.material.status === MaterialStatus.EMPTY || this.material.status === MaterialStatus.DISCARDED) {
      return 'handled';
    }
    if (levelOf(this.material) === ExpiryLevel.EXPIRED) {
      return 'expired';
    }
    return 'normal';
  }

  build() {
    HardShadowCard({shadowMode: 72, onCardClick: () => {
      this.onOpen();
    }}) {
      if (this.variant() === 'expired') {
        this.expiredBody()
      } else if (this.variant() === 'handled') {
        this.handledBody()
      } else {
        this.normalBody()
      }
    }
  }

  /** 开封标记：开封物品在卡片名称行尾部显示（黄底黑边小方标） */
  @Builder
  openedBadge() {
    Text('开封')
      .fontSize(Theme.textTiny)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.ink)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(Theme.yellowDark)
      .border(Theme.borderThin)
  }

  /** 几何状态形状：过期=红圆 / 临期=橙三角 / 安全=蓝绿方 */
  @Builder
  geoShape(level: ExpiryLevel) {
    if (level === ExpiryLevel.EXPIRED) {
      Circle({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.expired)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else if (level === ExpiryLevel.NEAR) {
      // 等腰三角形：原生 Polygon（画布坐标系不随 vp 缩放，高分屏上会画得又小又偏，勿回退 Canvas+Path）
      Polygon({ width: Theme.geoSize, height: Theme.geoSize })
        .points([[Theme.geoSize / 2, 0], [Theme.geoSize, Theme.geoSize], [0, Theme.geoSize]])
        .fill(Theme.near)
        .stroke(Theme.ink)
        .strokeWidth(2)
    } else {
      // 正方形
      Rect({ width: Theme.geoSize, height: Theme.geoSize })
        .fill(Theme.safe)
        .stroke(Theme.ink)
        .strokeWidth(2)
    }
  }

  /** 过期卡：红底白字 */
  @Builder
  expiredBody() {
    Row() {
      Column() {
        SymbolGlyph(getCategoryIcon(this.material.category).symbol)
          .fontSize(22)
          .fontColor([Theme.textWhite])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .border({ width: 2, color: Theme.textWhite })
      .margin({ right: Theme.elementGap })

      Column({ space: Theme.tinyGap }) {
        Row({ space: Theme.smallGap }) {
          Text(this.material.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.material.status === MaterialStatus.OPENED) {
            this.openedBadge()
          }
        }
        Text(`${this.material.category} · ${this.material.quantity}${this.material.unit} · ${this.material.expiryDate}`)
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textWhiteDim)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        Text(`-${-remainingDays(this.material)}天`)
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

  /** 临期/安全卡：白底黑边 + 左侧几何标识 + 分类图标 */
  @Builder
  normalBody() {
    Row() {
      Stack() {
        this.geoShape(levelOf(this.material))
      }
      .margin({ right: Theme.elementGap })

      Column() {
        SymbolGlyph(getCategoryIcon(this.material.category).symbol)
          .fontSize(20)
          .fontColor([Theme.ink])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .border({ width: 2, color: Theme.ink })
      .backgroundColor(getCategoryIcon(this.material.category).bgColor)
      .margin({ right: Theme.elementGap })

      Column({ space: Theme.tinyGap }) {
        Row({ space: Theme.smallGap }) {
          Text(this.material.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.material.status === MaterialStatus.OPENED) {
            this.openedBadge()
          }
        }
        Text(this.material.location.length > 0
          ? `${this.material.category} · ${this.material.location} · ${this.material.quantity}${this.material.unit}`
          : `${this.material.category} · ${this.material.quantity}${this.material.unit}`)
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        Text(`${remainingDays(this.material)}天`)
          .fontSize(Theme.textHeadline)
          .fontWeight(FontWeight.Bold)
          .fontColor(levelOf(this.material) === ExpiryLevel.NEAR ? Theme.near : Theme.safe)
        Text(this.material.expiryDate)
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

  /** 已处理卡：白底黑边 + 对勾图标 + 状态标签，整体降透明度 */
  @Builder
  handledBody() {
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
        Text(this.material.name)
          .fontSize(Theme.textBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.material.category} · ${this.material.quantity}${this.material.unit}`)
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.material.status === MaterialStatus.DISCARDED ? '已丢弃' : '已用完')
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
}
