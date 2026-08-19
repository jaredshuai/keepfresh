/**
 * 新增 / 编辑物资页 —— 鸿蒙官方设计风格。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, DEFAULT_CATEGORIES, DEFAULT_UNITS, SHELF_PRESET_DAYS } from '../model/Material';
import { MaterialDb } from '../db/MaterialDb';
import { calcExpiryDate } from '../service/ExpiryService';
import { toDateStr, todayStr, parseDate } from '../common/DateUtils';

interface RouteParams {
  id?: number;
}

const CLR_BRAND = '#2FA84F';
const CLR_BG = '#F1F3F5';
const CLR_CARD = '#FFFFFF';
const CLR_TEXT = '#182431';
const CLR_TEXT_SUB = '#99182431';
const CLR_TEXT_TIP = '#4D182431';
const CLR_INPUT_BG = '#F1F3F5';
const CLR_DANGER = '#FA2A2D';
const CLR_PREVIEW_BG = '#E8F5EF';

@Entry
@Component
struct AddItem {
  @State isEdit: boolean = false;
  @State name: string = '';
  @State category: string = DEFAULT_CATEGORIES[0];
  @State quantityStr: string = '1';
  @State unit: string = DEFAULT_UNITS[0];
  @State productionDate: string = todayStr();
  @State shelfLifeStr: string = '30';
  @State note: string = '';
  @State saving: boolean = false;
  @State errorMsg: string = '';
  private db: MaterialDb = MaterialDb.getInstance();
  private editId: number = -1;
  private loadedCreatedAt: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as RouteParams;
    if (params && params.id !== undefined) {
      this.editId = params.id;
      this.isEdit = true;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.db.init(ctx)
        .then(() => {
          return this.db.getById(this.editId);
        })
        .then((m?: Material) => {
          if (m) {
            this.name = m.name;
            this.category = m.category;
            this.quantityStr = m.quantity.toString();
            this.unit = m.unit;
            this.productionDate = m.productionDate;
            this.shelfLifeStr = m.shelfLifeDays.toString();
            this.note = m.note;
            this.loadedCreatedAt = m.createdAt;
          }
        })
        .catch((e: BusinessError) => {
          console.error(`load material failed: ${e.message}`);
        });
    }
  }

  private pickProductionDate(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-01-01'),
      end: new Date('2035-12-31'),
      selected: parseDate(this.productionDate),
      onDateAccept: (value: Date) => {
        this.productionDate = toDateStr(value);
      }
    });
  }

  private expiryPreview(): string {
    const days = Number(this.shelfLifeStr);
    if (this.shelfLifeStr === '' || Number.isNaN(days) || days < 1) {
      return '—';
    }
    return calcExpiryDate(this.productionDate, Math.floor(days));
  }

  private presetLabels(): string[] {
    return SHELF_PRESET_DAYS.map((d: number): string => `${d}天`);
  }

  async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    const qty = Number(this.quantityStr);
    const days = Number(this.shelfLifeStr);
    if (this.name.trim().length === 0) {
      this.errorMsg = '请输入物资名称';
      return;
    }
    if (this.quantityStr === '' || Number.isNaN(qty) || qty <= 0) {
      this.errorMsg = '数量需大于 0';
      return;
    }
    if (this.shelfLifeStr === '' || Number.isNaN(days) || days < 1) {
      this.errorMsg = '保质期需至少 1 天';
      return;
    }
    this.errorMsg = '';
    this.saving = true;
    const now = todayStr();
    const material: Material = {
      id: this.editId,
      name: this.name.trim(),
      category: this.category,
      quantity: qty,
      unit: this.unit,
      productionDate: this.productionDate,
      shelfLifeDays: Math.floor(days),
      expiryDate: calcExpiryDate(this.productionDate, Math.floor(days)),
      note: this.note.trim(),
      createdAt: this.isEdit ? this.loadedCreatedAt : now,
      updatedAt: now
    };
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.db.init(ctx);
      if (this.isEdit) {
        await this.db.update(material);
      } else {
        await this.db.insert(material);
      }
      this.getUIContext().showToast({ message: this.isEdit ? '已保存' : '已添加' });
      router.back();
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.errorMsg = `保存失败：${err.message}`;
      console.error(`save failed: ${err.message}`);
    } finally {
      this.saving = false;
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
        Text(this.isEdit ? '编辑物资' : '新增物资')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(CLR_TEXT)
          .margin({ left: 4 })
        Blank()
        if (this.saving) {
          LoadingProgress().width(20).height(20).color(CLR_BRAND).margin({ right: 8 })
        }
        Button(this.isEdit ? '保存' : '添加')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(CLR_BRAND)
          .borderRadius(20)
          .height(38)
          .padding({ left: 20, right: 20 })
          .enabled(!this.saving)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          if (this.errorMsg !== '') {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor(CLR_DANGER)
              .width('100%')
          }

          Column() {
            this.fieldLabel('物资名称 *')
            TextInput({ text: this.name, placeholder: '如：牛奶、感冒灵、洗面奶' })
              .fontSize(16)
              .backgroundColor(CLR_INPUT_BG)
              .borderRadius(12)
              .onChange((v: string) => {
                this.name = v;
              })

            this.fieldLabel('分类')
            this.chipGroup(DEFAULT_CATEGORIES, this.category, (v: string) => {
              this.category = v;
            })

            this.fieldLabel('数量 *')
            TextInput({ text: this.quantityStr, placeholder: '数量' })
              .type(InputType.Number)
              .fontSize(16)
              .backgroundColor(CLR_INPUT_BG)
              .borderRadius(12)
              .onChange((v: string) => {
                this.quantityStr = v;
              })
            this.chipGroup(DEFAULT_UNITS, this.unit, (v: string) => {
              this.unit = v;
            })

            this.fieldLabel('生产日期 *')
            Row() {
              Text(this.productionDate)
                .fontSize(16)
                .fontColor(CLR_TEXT)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(20)
                .fontColor([CLR_BRAND])
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor(CLR_INPUT_BG)
            .onClick(() => {
              this.pickProductionDate();
            })

            this.fieldLabel('保质期（天）*')
            TextInput({ text: this.shelfLifeStr, placeholder: '天数' })
              .type(InputType.Number)
              .fontSize(16)
              .backgroundColor(CLR_INPUT_BG)
              .borderRadius(12)
              .onChange((v: string) => {
                this.shelfLifeStr = v;
              })
            this.chipGroup(this.presetLabels(), `${this.shelfLifeStr}天`, (v: string) => {
              this.shelfLifeStr = v.replace('天', '');
            })

            Row() {
              Text('预计到期日')
                .fontSize(14)
                .fontColor(CLR_TEXT_SUB)
              Blank()
              Text(this.expiryPreview())
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(CLR_BRAND)
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor(CLR_PREVIEW_BG)
            .margin({ top: 4 })

            this.fieldLabel('备注')
            TextArea({ text: this.note, placeholder: '选填' })
              .fontSize(16)
              .backgroundColor(CLR_INPUT_BG)
              .borderRadius(12)
              .height(88)
              .onChange((v: string) => {
                this.note = v;
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(CLR_CARD)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 30 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CLR_BG)
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(CLR_TEXT_SUB)
      .margin({ top: 16, bottom: 8 })
  }

  @Builder
  chipGroup(options: string[], selected: string, onSelect: (v: string) => void) {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(options, (opt: string) => {
        Text(opt)
          .fontSize(13)
          .fontColor(selected === opt ? Color.White : CLR_TEXT)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .backgroundColor(selected === opt ? CLR_BRAND : CLR_INPUT_BG)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            onSelect(opt);
          })
      }, (opt: string) => opt)
    }
    .width('100%')
  }
}
