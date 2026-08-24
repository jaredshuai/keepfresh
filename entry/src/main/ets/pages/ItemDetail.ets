/**
 * 物资详情页：信息展示 + 编辑入口 + 删除 —— 清新自然风格。
 */
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material } from '../model/Material';
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
      const params = router.getParams() as RouteParams;
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
      ReminderService.getInstance().syncDailyReminder(ctx);
      promptAction.showToast({ message: '已删除' });
      router.back();
    } catch (e) {
      console.error(`delete failed: ${(e as BusinessError).message}`);
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([Theme.textPrimary])
        }
        .backgroundColor(Theme.inputBg)
        .width(Theme.iconBtnSize)
        .height(Theme.iconBtnSize)
        .onClick(() => {
          router.back();
        })

        Text('物资详情')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.smallGap })

        Blank()
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding - 4,
        right: Theme.pagePadding,
        top: 12,
        bottom: 12
      })

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(Theme.brand)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.m) {
        Scroll() {
          Column({ space: Theme.cardGap }) {
            this.statusBanner()
            this.infoCard()

            Row({ space: Theme.elementGap }) {
              Button('编辑')
                .layoutWeight(1)
                .height(Theme.primaryBtnHeight)
                .borderRadius(Theme.buttonRadius)
                .backgroundColor(Theme.brand)
                .fontColor(Color.White)
                .fontSize(Theme.textBody)
                .shadow(Theme.buttonShadow)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/AddItem', params: { id: this.itemId } });
                })

              Button('删除')
                .layoutWeight(1)
                .height(Theme.primaryBtnHeight)
                .borderRadius(Theme.buttonRadius)
                .backgroundColor(Theme.cardBg)
                .fontColor(Theme.danger)
                .fontSize(Theme.textBody)
                .border({ width: 1.5, color: Theme.danger })
                .onClick(() => {
                  this.confirmDelete();
                })
            }
            .width('100%')
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
  statusBanner() {
    const lv = levelOf(this.m!);
    const left = remainingDays(this.m!);

    Column({ space: Theme.smallGap }) {
      SymbolGlyph(lv === ExpiryLevel.EXPIRED
        ? $r('sys.symbol.exclamationmark_triangle')
        : (lv === ExpiryLevel.NEAR
            ? $r('sys.symbol.clock')
            : $r('sys.symbol.checkmark_seal')))
        .fontSize(48)
        .fontColor([Theme.textWhite])
        .opacity(0.9)

      Text(levelText(lv, left))
        .fontSize(Theme.textHero)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textWhite)
        .margin({ top: 4 })

      Text(`${this.m!.expiryDate} 到期`)
        .fontSize(Theme.textBody)
        .fontColor(Theme.textWhite)
        .opacity(0.9)
    }
    .width('100%')
    .padding(Theme.cardPadding)
    .padding({ top: 32, bottom: 32 })
    .borderRadius(Theme.cardRadius)
    .backgroundColor(levelColor(lv))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  infoCard() {
    const iconInfo = getCategoryIcon(this.m!.category);

    Column({ space: Theme.elementGap }) {
      // 名称 + 分类
      Row({ space: Theme.elementGap }) {
        Column() {
          SymbolGlyph(iconInfo.symbol)
            .fontSize(24)
            .fontColor([Theme.brand])
        }
        .width(52)
        .height(52)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(iconInfo.bgColor)
        .justifyContent(FlexAlign.Center)

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

      Divider().color(Theme.divider).strokeWidth(1)

      this.infoRow('生产日期', this.m!.productionDate)
      this.infoRow('保质期', `${this.m!.shelfLifeDays} 天`)
      this.infoRow('到期日期', this.m!.expiryDate)
      this.infoRow('距到期', remainingText(this.m!))
      if (this.m!.barcode && this.m!.barcode.trim().length > 0) {
        this.infoRow('条形码', this.m!.barcode)
      }

      ForEach(this.customFieldsDefs, (def: CustomField) => {
        if (this.hasCustomFieldValue(def.id)) {
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
      }

      Divider().color(Theme.divider).strokeWidth(1)
      this.infoRow('创建于', this.m!.createdAt)
    }
    .width('100%')
    .padding(Theme.cardPadding)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.cardBg)
    .shadow(Theme.shadowStyle)
    .alignItems(HorizontalAlign.Start)
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
    .padding({ top: 10, bottom: 10 })
  }
}
