/**
 * 物资详情页：信息展示 + 编辑入口 + 删除 —— 包豪斯（Bauhaus）风格。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, ExpiryLevel } from '../model/Material';
import { CustomField } from '../model/CustomField';
import { MaterialDb } from '../db/MaterialDb';
import { levelOf, levelColor, levelSoftColor, levelText, remainingDays, remainingText } from '../service/ExpiryService';
import { ReminderService } from '../service/ReminderService';
import { Theme } from '../common/Theme';
import { getCategoryIcon } from '../common/CategoryIcons';

interface RouteParams {
  id?: number;
}

@Entry
@Component
struct ItemDetail {
  @State m: Material | undefined = undefined;
  @State customFieldsDefs: CustomField[] = [];
  @State loading: boolean = true;
  private db: MaterialDb = MaterialDb.getInstance();
  private itemId: number = -1;

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
      message: `确定删除「${this.m?.name}」吗？删除后不可恢复。`,
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
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error(`delete failed: ${(e as BusinessError).message}`);
    }
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
    .backgroundColor(Theme.pageBg)
  }

  @Builder
  backButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
      }
      .width(Theme.iconBtnSize)
      .height(Theme.iconBtnSize)
      .backgroundColor(Theme.ink)
      .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

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
    .width(Theme.iconBtnSize + Theme.hardShadowOffset)
    .height(Theme.iconBtnSize + Theme.hardShadowOffset)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
  }

  @Builder
  statusBanner() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.ink)
      .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Column({ space: Theme.smallGap }) {
        Row() {
          this.geoShape(levelOf(this.m!))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Text(levelText(levelOf(this.m!), remainingDays(this.m!)))
          .fontSize(Theme.statNumber)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textWhite)
          .margin({ top: Theme.smallGap })

        Text(`${this.m!.expiryDate} 到期`)
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
      .backgroundColor(levelColor(levelOf(this.m!)))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
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
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.ink)
      .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

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
            Text(`${this.m!.category} · ${this.m!.quantity} ${this.m!.unit}`)
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
        this.infoRow('保质期', `${this.m!.shelfLifeDays} 天`)
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
    .width('100%')
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
  }

  private hasCustomFieldValue(fieldId: string): boolean {
    if (!this.m || !this.m.customFields) {
      return false;
    }
    const val = this.m.customFields[fieldId];
    return val !== undefined && val.trim().length > 0;
  }

  private getCustomFieldValue(fieldId: string): string {
    if (!this.m || !this.m.customFields) {
      return '';
    }
    return this.m.customFields[fieldId] || '';
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

      Button(text)
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
