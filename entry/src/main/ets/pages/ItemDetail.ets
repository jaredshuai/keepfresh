/**
 * 物资详情页：信息展示 + 编辑入口 + 删除 —— 鸿蒙官方设计风格。
 */
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material } from '../model/Material';
import { CustomField } from '../model/CustomField';
import { MaterialDb } from '../db/MaterialDb';
import { levelOf, levelColor, levelText, remainingDays, remainingText } from '../service/ExpiryService';
import { ReminderService } from '../service/ReminderService';

interface RouteParams {
  id?: number;
}

const CLR_BRAND = '#2FA84F';
const CLR_BG = '#F1F3F5';
const CLR_CARD = '#FFFFFF';
const CLR_TEXT = '#182431';
const CLR_TEXT_SUB = '#99182431';
const CLR_DANGER = '#FA2A2D';

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
        fontColor: CLR_DANGER,
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
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([CLR_TEXT])
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            router.back();
          })
        Text('物资详情')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(CLR_TEXT)
          .margin({ left: 4 })
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 12 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(CLR_BRAND)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.m) {
        Scroll() {
          Column({ space: 16 }) {
            Column() {
              Text(levelText(levelOf(this.m), remainingDays(this.m)))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(`${this.m.expiryDate} 到期`)
                .fontSize(14)
                .fontColor('rgba(255,255,255,0.9)')
                .margin({ top: 6 })
            }
            .width('100%')
            .padding(24)
            .borderRadius(16)
            .backgroundColor(levelColor(levelOf(this.m)))
            .alignItems(HorizontalAlign.Center)

            Column() {
              Text(this.m.name)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(CLR_TEXT)
                .margin({ bottom: 6 })
              this.infoRow('分类', this.m.category)
              this.infoRow('数量', `${this.m.quantity} ${this.m.unit}`)
              this.infoRow('生产日期', this.m.productionDate)
              this.infoRow('保质期', `${this.m.shelfLifeDays} 天`)
              this.infoRow('到期日期', this.m.expiryDate)
              this.infoRow('距到期', remainingText(this.m))
              if (this.m.barcode && this.m.barcode.trim().length > 0) {
                this.infoRow('条形码', this.m.barcode)
              }
              ForEach(this.customFieldsDefs, (def: CustomField) => {
                if (this.hasCustomFieldValue(def.id)) {
                  this.infoRow(def.name, this.getCustomFieldValue(def.id))
                }
              }, (def: CustomField) => def.id)
              if (this.m.note !== '') {
                this.infoRow('备注', this.m.note)
              }
              this.infoRow('创建于', this.m.createdAt)
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(CLR_CARD)
            .alignItems(HorizontalAlign.Start)

            Row({ space: 12 }) {
              Button('编辑')
                .layoutWeight(1)
                .height(48)
                .borderRadius(24)
                .backgroundColor(CLR_BRAND)
                .fontColor(Color.White)
                .fontSize(16)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/AddItem', params: { id: this.itemId } });
                })
              Button('删除')
                .layoutWeight(1)
                .height(48)
                .borderRadius(24)
                .backgroundColor(CLR_CARD)
                .fontColor(CLR_DANGER)
                .fontSize(16)
                .border({ width: 1.5, color: CLR_DANGER })
                .onClick(() => {
                  this.confirmDelete();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 30 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      } else {
        Column() {
          Text('物资不存在或已删除')
            .fontSize(16)
            .fontColor(CLR_TEXT_SUB)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CLR_BG)
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
        .fontSize(15)
        .fontColor(CLR_TEXT_SUB)
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor(CLR_TEXT)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }
}
