/**
 * 包豪斯硬阴影容器（ticket #15）。
 *
 * 只接管「黑色偏移阴影层 + Stack + 右下补位」这一固定样板；
 * 主层（带背景/边框/padding/点击）整体留在调用方的尾随闭包里，
 * 组件不包装、不改写主层任何属性——替换前后布局逐像素一致。
 *
 * 两个变体对应 survey 聚类：
 * - HardShadowCard：外层 Stack width('100%') 的全宽卡（页面卡片/横幅/全宽按钮）
 * - HardShadowBox ：外层定尺寸的方块（图标按钮/FAB/输入框），外层尺寸 = 内尺寸 + 偏移
 *
 * 注意：pages/ 内禁止再手写 `margin({ left: Theme.hardShadowOffset`
 * 样板（design-guard 防回潮规则执法，白名单仅限登记过的复用型 builder）。
 */
import { Theme } from './Theme';

@Builder
function emptyShadowContent() {
}

@Component
export struct HardShadowCard {
  /**
   * 阴影层固定高度（vp）；0 = 不设 height（阴影层贴齐主层内容，绝大多数场景用这个）。
   * 禁止传 -1/'100%' 之类的百分比语义：height('100%') 在滚动容器里解析为
   * 「父约束的最大可用高度」而非主层高度，会把阴影撑成整屏黑板（#布局评审教训）。
   */
  @Prop shadowMode: number = 0;
  /** 原 Stack 使用 TopStart 对齐时传 true（默认 false = Center） */
  @Prop topStart: boolean = false;
  /** 卡片点击（还原原外层 Stack 的 onClick；无点击场景留默认空实现） */
  onCardClick: () => void = () => {};
  @BuilderParam content: () => void = emptyShadowContent;

  build() {
    Stack({ alignContent: this.topStart ? Alignment.TopStart : Alignment.Center }) {
      if (this.shadowMode > 0) {
        Column()
          .width('100%')
          .height(this.shadowMode)
          .backgroundColor(Theme.ink)
          .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
      } else {
        Column()
          .width('100%')
          .backgroundColor(Theme.ink)
          .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
      }
      this.content()
    }
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(() => this.onCardClick())
  }
}

@Component
export struct HardShadowBox {
  /** 主内容方块尺寸（vp），阴影层与外层尺寸由它推导 */
  @Prop boxWidth: number = 0;
  @Prop boxHeight: number = 0;
  /** 原 Stack 使用 TopStart 对齐时传 true（默认 false = Center） */
  @Prop topStart: boolean = false;
  /** 点击回调（如图标按钮/FAB 的 onClick 参数） */
  onBoxClick: () => void = () => {};
  @BuilderParam content: () => void = emptyShadowContent;

  build() {
    Stack({ alignContent: this.topStart ? Alignment.TopStart : Alignment.Center }) {
      Column()
        .width(this.boxWidth)
        .height(this.boxHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      this.content()
    }
    .width(this.boxWidth + Theme.hardShadowOffset)
    .height(this.boxHeight + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
    .onClick(() => this.onBoxClick())
  }
}
