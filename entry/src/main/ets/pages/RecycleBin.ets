/**
 * 回收站页 —— 包豪斯（Bauhaus）风格。
 * 软删除物资列表：恢复 / 彻底删除（二次确认）。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, MaterialStatus } from '../model/Material';
import { MaterialDb } from '../db/MaterialDb';
import { Theme } from '../common/Theme';
import { HardShadowBox, HardShadowCard } from '../common/HardShadow';

@Entry
@Component
struct RecycleBin {
  @StorageProp('avoidTopVp') avoidTopVp: number = 0;
  @StorageProp('avoidBottomVp') avoidBottomVp: number = 0;
  @State deleted: Material[] = [];
  @State loading: boolean = true;
  @State restoringId: number = -1;
  private db: MaterialDb = MaterialDb.getInstance();

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error(`show toast failed: ${(e as BusinessError).message}`);
    }
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.db.init(ctx)
      .then(() => {
        return this.load();
      })
      .catch((e: BusinessError) => {
        console.error(`init db failed: ${e.message}`);
        this.loading = false;
      });
  }

  private async load(): Promise<void> {
    try {
      this.deleted = await this.db.listDeleted();
    } catch (e) {
      console.error(`load deleted failed: ${(e as BusinessError).message}`);
    } finally {
      this.loading = false;
    }
  }

  private async restore(id: number): Promise<void> {
    if (this.restoringId >= 0) {
      return;
    }
    this.restoringId = id;
    try {
      await this.db.restore(id);
      this.toast('已恢复');
      this.load();
    } catch (e) {
      console.error(`restore failed: ${(e as BusinessError).message}`);
      this.toast('恢复失败，请重试');
    } finally {
      this.restoringId = -1;
    }
  }

  private confirmPurge(m: Material): void {
    this.getUIContext().showAlertDialog({
      title: '彻底删除',
      message: `确定彻底删除「${m.name}」吗？此操作不可恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '彻底删除',
        fontColor: Theme.danger,
        action: () => {
          this.doPurge(m);
        }
      }
    });
  }

  private async doPurge(m: Material): Promise<void> {
    try {
      await this.db.purge(m.id);
      this.toast('已彻底删除');
      this.load();
    } catch (e) {
      console.error(`purge failed: ${(e as BusinessError).message}`);
    }
  }

  build() {
    Column() {
      // 顶部导航：返回 + 标题
      Row() {
        this.backButton()

        Text('回收站')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.elementGap })
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding,
        right: Theme.pagePadding,
        top: 16,
        bottom: 12
      })

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(Theme.ink)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.deleted.length === 0) {
        Column({ space: Theme.smallGap }) {
          Rect({ width: 40, height: 40 })
            .fill(Theme.cardBg)
            .stroke(Theme.ink)
            .strokeWidth(2)
          Text('回收站是空的')
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary)
          Text('删除的物资会暂存在这里')
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textTertiary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: Theme.smallGap }) {
            Text(`${this.deleted.length} 件已删除物资`)
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textTertiary)
              .width('100%')
            ForEach(this.deleted, (m: Material) => {
              this.deletedCard(m)
            }, (m: Material) => m.id.toString())
            Column().width('100%').height(24)
          }
          .width('100%')
          .padding({ left: Theme.pagePadding, right: Theme.pagePadding })
        }
        .layoutWeight(1)
        // 内容不足一屏时靠顶对齐（Scroll 通用 align 默认 Center 会把短内容垂直居中）
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.avoidTopVp, bottom: this.avoidBottomVp })
    .backgroundColor(Theme.pageBg)
  }

  @Builder
  backButton() {
    HardShadowBox({ boxWidth: Theme.iconBtnSize, boxHeight: Theme.iconBtnSize, topStart: true }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
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

  /** 已删除物资卡片：半透明白卡 + 恢复（深黄）/ 彻底删除（白底红字） */
  @Builder
  deletedCard(m: Material) {
    HardShadowCard({ shadowMode: 0, topStart: true }) {
      Column({ space: Theme.smallGap }) {
        Row() {
          Column({ space: Theme.tinyGap }) {
            Text(m.name)
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${m.category} · ${m.quantity}${m.unit} · ${m.expiryDate} 到期`)
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (m.status === MaterialStatus.EMPTY || m.status === MaterialStatus.DISCARDED) {
            Text(m.status === MaterialStatus.DISCARDED ? '丢弃' : '用完')
              .fontSize(Theme.textTiny)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textSecondary)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .border({ width: 1, color: Theme.textTertiary })
          }
        }
        .width('100%')

        Row({ space: Theme.smallGap }) {
          Text('恢复')
            .fontSize(Theme.textSmall)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .backgroundColor(Theme.yellowDark)
            .border(Theme.borderThin)
            .onClick(() => {
              this.restore(m.id);
            })
          Text('彻底删除')
            .fontSize(Theme.textSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.danger)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(Theme.cardBg)
            .border(Theme.borderThin)
            .onClick(() => {
              this.confirmPurge(m);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .alignItems(HorizontalAlign.Start)
      .opacity(0.85)
    }
  }
}
