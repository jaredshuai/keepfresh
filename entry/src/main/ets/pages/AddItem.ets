/**
 * 新增 / 编辑物资页 —— 鸿蒙官方设计风格。
 */
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, DEFAULT_CATEGORIES, DEFAULT_UNITS, SHELF_PRESET_DAYS } from '../model/Material';
import { CustomField, validateCustomFieldValue } from '../model/CustomField';
import { MaterialDb } from '../db/MaterialDb';
import { calcExpiryDate } from '../service/ExpiryService';
import { toDateStr, todayStr, parseDate } from '../common/DateUtils';
import { scanForSuggestions, ScanFillResult } from '../service/ScanService';
import { ReminderService } from '../service/ReminderService';

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

/** ArkTS 禁用对象展开（arkts-no-spread）：逐键拷贝 Record */
function copyStringRecord(src: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  const keys: string[] = Object.keys(src);
  for (let i = 0; i < keys.length; i++) {
    out[keys[i]] = src[keys[i]];
  }
  return out;
}

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
  @State barcode: string = '';
  @State showScanSheet: boolean = false;
  @State scanSuggestions: Material[] = [];
  @State saving: boolean = false;
  @State errorMsg: string = '';
  @State customFieldsDefs: CustomField[] = [];
  @State customFieldValues: Record<string, string> = {};
  private db: MaterialDb = MaterialDb.getInstance();
  private editId: number = -1;
  private loadedCreatedAt: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as RouteParams;
    if (params && params.id !== undefined) {
      this.editId = params.id;
      this.isEdit = true;
    }

    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.db.init(ctx)
      .then(() => {
        return this.db.listCustomFields();
      })
      .then((defs: CustomField[]) => {
        this.customFieldsDefs = defs;
        if (this.editId >= 0) {
          return this.db.getById(this.editId);
        }
        return undefined;
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
          this.barcode = m.barcode || '';
          if (m.customFields) {
            this.customFieldValues = copyStringRecord(m.customFields);
          }
        }
      })
      .catch((e: BusinessError) => {
        console.error(`load material or custom fields failed: ${e.message}`);
      });
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

  private pickCustomFieldDate(fieldId: string): void {
    const currentVal = this.customFieldValues[fieldId];
    const selectedDate = currentVal ? parseDate(currentVal) : new Date();
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-01-01'),
      end: new Date('2035-12-31'),
      selected: selectedDate,
      onDateAccept: (value: Date) => {
        const copy: Record<string, string> = copyStringRecord(this.customFieldValues);
        copy[fieldId] = toDateStr(value);
        this.customFieldValues = copy;
      }
    });
  }

  private selectCustomEnumOption(fieldId: string, opt: string): void {
    const copy: Record<string, string> = copyStringRecord(this.customFieldValues);
    if (copy[fieldId] === opt) {
      copy[fieldId] = '';
    } else {
      copy[fieldId] = opt;
    }
    this.customFieldValues = copy;
  }

  private updateCustomFieldValue(fieldId: string, value: string): void {
    const copy: Record<string, string> = copyStringRecord(this.customFieldValues);
    copy[fieldId] = value;
    this.customFieldValues = copy;
  }

  private async handleScanBarcode(): Promise<void> {
    if (this.saving) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.db.init(ctx);
    const result: ScanFillResult | undefined = await scanForSuggestions(ctx, this.db);
    if (!result) {
      return; // 用户取消扫码
    }
    if (!result.ok) {
      promptAction.showToast({ message: '扫码失败或设备不支持，请手动填写' });
      return;
    }
    this.barcode = result.barcode;
    if (result.suggestions.length === 0) {
      // 陌生条码：不预填，条码随本条物资记录一并保存
      this.scanSuggestions = [];
      promptAction.showToast({ message: '该条码无历史记录，请手动填写' });
      return;
    }
    this.scanSuggestions = result.suggestions;
    this.showScanSheet = true;
  }

  /** 点选搜索建议：预填名称/分类/单位/保质期天数，生产日期和数量留给用户 */
  private applyScanSuggestion(m: Material): void {
    this.name = m.name;
    this.category = m.category;
    this.unit = m.unit;
    this.shelfLifeStr = m.shelfLifeDays.toString();
    this.showScanSheet = false;
    promptAction.showToast({ message: '已预填，请补充生产日期和数量' });
  }

  /** 「都不对，手动填写」：丢弃预填，仅保留条码 */
  private discardScanSuggestions(): void {
    this.showScanSheet = false;
    promptAction.showToast({ message: '请手动填写物资信息' });
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
    for (const def of this.customFieldsDefs) {
      const val = this.customFieldValues[def.id] || '';
      const err = validateCustomFieldValue(def, val);
      if (err) {
        this.errorMsg = err;
        return;
      }
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
      updatedAt: now,
      barcode: this.barcode.trim().length > 0 ? this.barcode.trim() : undefined,
      customFields: this.customFieldValues
    };
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.db.init(ctx);
      if (this.isEdit) {
        await this.db.update(material);
      } else {
        await this.db.insert(material);
      }
      ReminderService.getInstance().syncDailyReminder(ctx);
      promptAction.showToast({ message: this.isEdit ? '已保存' : '已添加' });
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

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.camera'))
                .fontSize(16)
                .fontColor([Color.White])
              Text('扫码快填')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
          }
          .width('100%')
          .height(44)
          .borderRadius(22)
          .backgroundColor(CLR_BRAND)
          .onClick(() => {
            this.handleScanBarcode();
          })

          Column() {
            this.fieldLabel('物资名称 *')
            TextInput({ text: this.name, placeholder: '如：牛奶、感冒灵、洗面奶' })
              .fontSize(16)
              .backgroundColor(CLR_INPUT_BG)
              .borderRadius(12)
              .onChange((v: string) => {
                this.name = v;
              })

            if (this.barcode.trim().length > 0) {
              this.fieldLabel('条形码')
              Row() {
                Text(this.barcode)
                  .fontSize(15)
                  .fontColor(CLR_TEXT)
                  .layoutWeight(1)
                Text('清除')
                  .fontSize(13)
                  .fontColor(CLR_DANGER)
                  .padding({ left: 8, right: 4, top: 4, bottom: 4 })
                  .onClick(() => {
                    this.barcode = '';
                  })
              }
              .width('100%')
              .padding(14)
              .borderRadius(12)
              .backgroundColor(CLR_INPUT_BG)
            }

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

            if (this.customFieldsDefs.length > 0) {
              ForEach(this.customFieldsDefs, (def: CustomField) => {
                this.renderCustomFieldInput(def)
              }, (def: CustomField) => def.id)
            }

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
    .bindSheet($$this.showScanSheet, this.scanSuggestionsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: CLR_CARD,
      onDisappear: () => {
        this.showScanSheet = false;
      }
    })
  }

  /** 扫码快填搜索建议半模态：历史入库记录列表 + 手动填写入口 */
  @Builder
  scanSuggestionsSheet() {
    Column() {
      Text('扫码快填')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(CLR_TEXT)
        .margin({ top: 8, bottom: 4 })
      Text(`条码 ${this.barcode} 匹配到历史入库记录，选择一条预填表单`)
        .fontSize(13)
        .fontColor(CLR_TEXT_SUB)
        .margin({ bottom: 12 })

      List({ space: 8 }) {
        ForEach(this.scanSuggestions, (m: Material) => {
          ListItem() {
            this.suggestionRow(m)
          }
        }, (m: Material) => m.id.toString())
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)

      Button('都不对，手动填写')
        .width('100%')
        .height(44)
        .borderRadius(12)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: CLR_BRAND })
        .fontSize(15)
        .fontColor(CLR_BRAND)
        .margin({ top: 16, bottom: 16 })
        .onClick(() => {
          this.discardScanSuggestions();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12 })
  }

  /** 单条搜索建议：名称 + 数量单位/保质期 + 最近入库时间 */
  @Builder
  suggestionRow(m: Material) {
    Row() {
      Column() {
        Text(m.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(CLR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${m.category} · ${m.quantity}${m.unit} · 保质期${m.shelfLifeDays}天`)
          .fontSize(12)
          .fontColor(CLR_TEXT_SUB)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text('最近入库')
          .fontSize(11)
          .fontColor(CLR_TEXT_TIP)
        Text(m.createdAt)
          .fontSize(13)
          .fontColor(CLR_TEXT_SUB)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(CLR_INPUT_BG)
    .onClick(() => {
      this.applyScanSuggestion(m);
    })
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

  @Builder
  renderCustomFieldInput(def: CustomField) {
    if (def.type === 'text') {
      this.fieldLabel(def.name)
      TextInput({ text: this.customFieldValues[def.id] || '', placeholder: '选填' })
        .fontSize(16)
        .backgroundColor(CLR_INPUT_BG)
        .borderRadius(12)
        .onChange((v: string) => {
          this.updateCustomFieldValue(def.id, v);
        })
    } else if (def.type === 'number') {
      this.fieldLabel(def.name)
      TextInput({ text: this.customFieldValues[def.id] || '', placeholder: '选填（数字）' })
        .type(InputType.Number)
        .fontSize(16)
        .backgroundColor(CLR_INPUT_BG)
        .borderRadius(12)
        .onChange((v: string) => {
          this.updateCustomFieldValue(def.id, v);
        })
    } else if (def.type === 'date') {
      this.fieldLabel(def.name)
      Row() {
        Text(this.customFieldValues[def.id] ? this.customFieldValues[def.id] : `选择${def.name}`)
          .fontSize(16)
          .fontColor(this.customFieldValues[def.id] ? CLR_TEXT : CLR_TEXT_TIP)
          .layoutWeight(1)
        if (this.customFieldValues[def.id] && this.customFieldValues[def.id].length > 0) {
          Text('清除')
            .fontSize(13)
            .fontColor(CLR_DANGER)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.updateCustomFieldValue(def.id, '');
            })
        }
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(20)
          .fontColor([CLR_BRAND])
      }
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor(CLR_INPUT_BG)
      .onClick(() => {
        this.pickCustomFieldDate(def.id);
      })
    } else if (def.type === 'enum') {
      this.fieldLabel(def.name)
      this.customEnumChipGroup(def.id, def.options || [])
    }
  }

  @Builder
  customEnumChipGroup(fieldId: string, options: string[]) {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(options, (opt: string) => {
        Text(opt)
          .fontSize(13)
          .fontColor(this.customFieldValues[fieldId] === opt ? Color.White : CLR_TEXT)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .backgroundColor(this.customFieldValues[fieldId] === opt ? CLR_BRAND : CLR_INPUT_BG)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.selectCustomEnumOption(fieldId, opt);
          })
      }, (opt: string) => opt)
    }
    .width('100%')
  }
}
