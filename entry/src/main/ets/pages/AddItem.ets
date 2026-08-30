/**
 * 新增 / 编辑物资页 —— 包豪斯（Bauhaus）设计风格。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, MaterialStatus, DateEntryMode, DEFAULT_CATEGORIES, DEFAULT_LOCATIONS, DEFAULT_UNITS, SHELF_PRESET_DAYS, SHELF_PRESET_MONTHS, batchQuantitySum } from '../model/Material';
import { CustomField, validateCustomFieldValue } from '../model/CustomField';
import { MaterialDb } from '../db/MaterialDb';
import { calcExpiryDate } from '../common/ExpiryService';
import { toDateStr, todayStr, parseDate } from '../common/DateUtils';
import { normalizeQuantityUnit, formatQuantityUnit } from '../common/QuantityUnit';
import { UsageService } from '../service/UsageService';
import { parseNonNegativeInteger } from '../common/InputNormalize';
import { scanForSuggestions, ScanFillResult } from '../service/ScanService';
import { ReminderService } from '../service/ReminderService';
import { Theme } from '../common/Theme';
import { HardShadowBox, HardShadowCard } from '../common/HardShadow';

interface RouteParams {
  id?: number;
}

/** ArkTS 禁用对象展开（arkts-no-spread）：逐键拷贝 Record */
function copyStringRecord(src: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  const keys: string[] = Object.keys(src);
  for (let i = 0; i < keys.length; i++) {
    out[keys[i]] = src[keys[i]];
  }
  return out;
}

/**
 * 换行铺开的单选芯片组（分类/位置/单位/保质期预设共用）。
 * 独立组件而非 @Builder：@Builder 按值传参不随状态刷新，选中高亮会停滞
 * （界面显示与实际保存值不一致，实测坑）；@Prop selected 由父状态驱动，响应式有保证。
 */
@Component
struct ChipGroup {
  @Prop options: string[] = [];
  @Prop selected: string = '';
  onSelect: (v: string) => void = () => {};

  build() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(this.options, (opt: string) => {
        Stack() {
          Row()
            .backgroundColor(Theme.ink)
            .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

          Text(opt)
            .fontSize(Theme.textCaption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selected === opt ? Theme.textWhite : Theme.textPrimary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(Theme.chipRadius)
            .backgroundColor(this.selected === opt ? Theme.yellowDark : Theme.inputBg)
            .border(Theme.borderThin)
            .onClick(() => {
              this.onSelect(opt);
            })
        }
        .margin({ right: Theme.smallGap + Theme.hardShadowOffset, bottom: Theme.smallGap + Theme.hardShadowOffset })
      }, (opt: string) => opt)
    }
    .width('100%')
  }
}

/**
 * 日期录入行（标签 + 触发行 + 可选说明文案），shelf 生产日期与 direct 到期日区块共用（#22 去重）。
 * 独立组件而非 @Builder：@Builder 按值传参不随状态刷新，日期显示会停滞
 * （#builder-by-value 实测坑）；@Prop value 由父状态驱动，响应式有保证（ChipGroup 先例）。
 */
@Component
struct DateFieldRow {
  @Prop label: string = '';
  @Prop value: string = '';
  caption: string = '';
  onPick: () => void = () => {};

  build() {
    Column({ space: Theme.elementGap }) {
      Text(this.label)
        .fontSize(Theme.textCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .margin({ bottom: Theme.tinyGap })

      HardShadowCard({shadowMode: 0}) {
        Row() {
          Text(this.value)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(20)
            .fontColor([Theme.near])
        }
        .width('100%')
        .padding(Theme.cardPadding)
        .backgroundColor(Theme.inputBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.inputRadius)
        .height(48)
        .onClick(() => {
          this.onPick();
        })
      }

      if (this.caption.length > 0) {
        Text(this.caption)
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textTertiary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Entry
@Component
struct AddItem {
  @StorageProp('avoidTopVp') avoidTopVp: number = 0;
  @StorageProp('avoidBottomVp') avoidBottomVp: number = 0;
  @State isEdit: boolean = false;
  @State name: string = '';
  @State category: string = DEFAULT_CATEGORIES[0];
  @State categories: string[] = DEFAULT_CATEGORIES.slice();
  @State quantityStr: string = '1';
  @State unit: string = DEFAULT_UNITS[0];
  @State units: string[] = DEFAULT_UNITS.slice();
  @State location: string = DEFAULT_LOCATIONS[2];
  @State locations: string[] = DEFAULT_LOCATIONS.slice();
  @State productionDate: string = todayStr();
  @State shelfLifeStr: string = '30';
  @State shelfLifeMode: string = 'days';       // 'days' | 'months'
  @State shelfLifeMonthsStr: string = '';
  @State dateMode: DateEntryMode = DateEntryMode.SHELF; // SHELF=生产日期+保质期推算 | DIRECT=包装只印到期日，直接录入
  @State directExpiryDate: string = todayStr(); // direct 模式的到期日期
  @State note: string = '';
  @State barcode: string = '';
  @State showScanSheet: boolean = false;
  @State scanSuggestions: Material[] = [];
  @State saving: boolean = false;
  @State errorMsg: string = '';
  /** 名称前缀联想候选（dogfood P0 演进）：输名称时按前缀匹配在库记录，点选预填 */
  @State nameCandidates: Material[] = [];
  @State customFieldsDefs: CustomField[] = [];
  @State customFieldValues: Record<string, string> = {};
  private db: MaterialDb = MaterialDb.getInstance();
  private editId: number = -1;
  private pageOpenAt: number = Date.now();
  private nameQuerySeq: number = 0;
  private suggestionApplied: boolean = false;
  private loadedCreatedAt: string = '';
  private loadedStatus: string = MaterialStatus.ACTIVE;
  private loadedHandledType: string | undefined = undefined;
  private loadedHandledAt: string | undefined = undefined;

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error(`show toast failed: ${(e as BusinessError).message}`);
    }
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as RouteParams;
    if (params && params.id !== undefined) {
      this.editId = params.id;
      this.isEdit = true;
    }

    this.pageOpenAt = Date.now();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UsageService.getInstance().init(ctx);
    this.db.init(ctx)
      .then(() => {
        // 分类候选：管理页自定义定义（按排序）→ 预设 → 数据中出现过的
        return this.db.listEffectiveNames('category', DEFAULT_CATEGORIES);
      })
      .then((cats: string[]) => {
        this.categories = cats;
        if (cats.indexOf(this.category) < 0 && cats.length > 0) {
          this.category = cats[0];
        }
        // 位置候选：同一合并口径
        return this.db.listEffectiveNames('location', DEFAULT_LOCATIONS);
      })
      .then((locs: string[]) => {
        this.locations = locs;
        if (locs.indexOf(this.location) < 0 && locs.length > 0) {
          this.location = locs[2] ?? locs[0];
        }
        // 单位候选：管理页自定义定义（按排序）→ 预设 → 数据中出现过的
        return this.db.listEffectiveNames('unit', DEFAULT_UNITS);
      })
      .then((unitCandidates: string[]) => {
        this.units = unitCandidates;
        if (unitCandidates.indexOf(this.unit) < 0 && unitCandidates.length > 0) {
          this.unit = unitCandidates[0];
        }
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
          const normalized = normalizeQuantityUnit(m.quantity, m.unit);
          this.quantityStr = normalized.quantity;
          if (normalized.unit.length > 0) {
            this.unit = normalized.unit;
          }
          this.location = m.location && m.location.length > 0 ? m.location : DEFAULT_LOCATIONS[2];
          if (m.productionDate.length === 0) {
            // direct 口径存量物品：包装只印到期日，直接回填到期日
            this.dateMode = DateEntryMode.DIRECT;
            this.directExpiryDate = m.expiryDate;
          } else {
            this.dateMode = DateEntryMode.SHELF;
            this.productionDate = m.productionDate;
            if (m.shelfLifeMonths !== undefined && m.shelfLifeMonths !== null && m.shelfLifeMonths > 0) {
              this.shelfLifeMode = 'months';
              this.shelfLifeMonthsStr = m.shelfLifeMonths.toString();
            } else {
              this.shelfLifeMode = 'days';
              this.shelfLifeStr = m.shelfLifeDays.toString();
            }
          }
          this.note = m.note;
          this.loadedCreatedAt = m.createdAt;
          this.loadedStatus = m.status ?? MaterialStatus.ACTIVE;
          this.loadedHandledType = m.handledType;
          this.loadedHandledAt = m.handledAt;
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

  /** 名称前缀联想：输 1 字起按前缀查在库记录，每名取最近一条最多 3 条（dogfood P0 演进） */
  private lookupNameCandidates(v: string): void {
    const trimmed = v.trim();
    if (this.isEdit || trimmed.length < 1) {
      this.nameCandidates = [];
      return;
    }
    const seq = ++this.nameQuerySeq;
    this.db.findActiveByNamePrefix(trimmed, 3)
      .then((list: Material[]) => {
        if (seq !== this.nameQuerySeq) {
          return; // 过期查询，丢弃
        }
        if (list.length > 0 && this.nameCandidates.length === 0) {
          UsageService.getInstance().logSuggestionShown(list[0].name);
        }
        this.nameCandidates = list;
      })
      .catch((e: BusinessError) => {
        console.error(`lookup name candidates failed: ${(e as BusinessError).message}`);
      });
  }

  private suggestionSummary(m: Material): string {
    const shelf = m.productionDate.length === 0
      ? `到期日 ${m.expiryDate}`
      : ((m.shelfLifeMonths !== undefined && m.shelfLifeMonths !== null && m.shelfLifeMonths > 0)
        ? `保质期${m.shelfLifeMonths}个月`
        : `保质期${m.shelfLifeDays}天`);
    const loc = m.location && m.location.length > 0 ? ` · ${m.location}` : '';
    return `${m.category}${loc} · ${m.quantity}${m.unit} · ${shelf}`;
  }

  private applyNameCandidate(m: Material): void {
    UsageService.getInstance().logSuggestionApplied(m.name);
    // 联想候选名可能比已输入的长（输「脉」选「脉动零糖白桃」），名称必须回填完整
    this.name = m.name;
    this.category = m.category;
    if (m.location && m.location.length > 0) {
      this.location = m.location;
    }
    const normalized = normalizeQuantityUnit(m.quantity, m.unit);
    this.quantityStr = normalized.quantity;
    if (normalized.unit.length > 0) {
      this.unit = normalized.unit;
    }
    if (m.productionDate.length === 0) {
      // direct 口径源记录：不带保质期字段，直接落到「直接填到期日」模式
      this.dateMode = DateEntryMode.DIRECT;
      this.directExpiryDate = m.expiryDate;
    } else {
      if (m.shelfLifeMonths !== undefined && m.shelfLifeMonths !== null && m.shelfLifeMonths > 0) {
        this.shelfLifeMode = 'months';
        this.shelfLifeMonthsStr = m.shelfLifeMonths.toString();
      } else {
        this.shelfLifeMode = 'days';
        this.shelfLifeStr = m.shelfLifeDays.toString();
      }
      // 生产日期预填历史值（同批次命中即免改；不同批次开选择器改，与留空成本相同）。
      // 不预填今天：生产日期几乎不可能是录入当天，today 是必错默认
      this.productionDate = m.productionDate;
      this.dateMode = DateEntryMode.SHELF;
    }
    this.suggestionApplied = true;
    this.nameCandidates = [];
    this.toast(m.productionDate.length === 0 ? '已按上次入库参数预填，请核对到期日' : '已按上次入库参数预填，请核对生产日期');
  }

  /** 共用日期选择包装（#22 去重）：只差 selected 与写回目标 */
  private pickDate(selected: string, onAccept: (dateStr: string) => void): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-01-01'),
      end: new Date('2035-12-31'),
      selected: parseDate(selected),
      onDateAccept: (value: Date) => {
        onAccept(toDateStr(value));
      }
    });
  }

  private pickProductionDate(): void {
    this.pickDate(this.productionDate, (d: string) => {
      this.productionDate = d;
    });
  }

  private pickDirectExpiryDate(): void {
    this.pickDate(this.directExpiryDate, (d: string) => {
      this.directExpiryDate = d;
    });
  }

  private expiryPreview(): string {
    if (this.dateMode === DateEntryMode.DIRECT) {
      return this.directExpiryDate;
    }
    if (this.shelfLifeMode === 'months') {
      const months = parseNonNegativeInteger(this.shelfLifeMonthsStr);
      if (months === null || months < 1) {
        return '—';
      }
      return calcExpiryDate(this.productionDate, 0, months);
    }
    const days = Number(this.shelfLifeStr);
    if (this.shelfLifeStr === '' || Number.isNaN(days) || days < 1) {
      return '—';
    }
    return calcExpiryDate(this.productionDate, Math.floor(days));
  }

  private presetLabels(): string[] {
    return SHELF_PRESET_DAYS.map((d: number): string => `${d}天`);
  }

  private presetMonthLabels(): string[] {
    return SHELF_PRESET_MONTHS.map((m: number): string => `${m}个月`);
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
    try {
      await this.db.init(ctx);
      const result: ScanFillResult | undefined = await scanForSuggestions(ctx, this.db);
      if (!result) {
        return;
      }
      if (!result.ok) {
        this.toast('扫码失败或设备不支持，请手动填写');
        return;
      }
      this.barcode = result.barcode;
      if (result.suggestions.length === 0) {
        this.scanSuggestions = [];
        this.toast('该条码无历史记录，请手动填写');
        return;
      }
      this.scanSuggestions = result.suggestions;
      this.showScanSheet = true;
    } catch (e) {
      console.error(`scan barcode failed: ${(e as BusinessError).message}`);
      this.toast('扫码失败，请手动填写');
    }
  }

  private applyScanSuggestion(m: Material): void {
    this.name = m.name;
    this.category = m.category;
    this.unit = m.unit;
    if (m.productionDate.length === 0) {
      // direct 口径源记录：不带保质期字段，直接落到「直接填到期日」模式并带出原到期日
      this.dateMode = DateEntryMode.DIRECT;
      this.directExpiryDate = m.expiryDate;
    } else {
      this.dateMode = DateEntryMode.SHELF;
      // 保质期口径还原：历史记录若按月数录入则保持月数模式（避免 365×n 天的错误近似）
      if (m.shelfLifeMonths !== undefined && m.shelfLifeMonths !== null && m.shelfLifeMonths > 0) {
        this.shelfLifeMode = 'months';
        this.shelfLifeMonthsStr = m.shelfLifeMonths.toString();
      } else {
        this.shelfLifeMode = 'days';
        this.shelfLifeStr = m.shelfLifeDays.toString();
      }
      // 同 applyNameCandidate：生产日期预填历史值，不猜今天
      this.productionDate = m.productionDate;
      this.dateMode = DateEntryMode.SHELF;
    }
    // 位置回填（历史记录有位置则带上；其位置已在 listEffectiveNames 合并结果内）
    if (m.location && m.location.length > 0) {
      this.location = m.location;
    }
    this.showScanSheet = false;
    this.toast(m.productionDate.length === 0 ? '已预填，请核对到期日和数量' : '已预填同款生产日期，不同批次请改日期');
  }

  private discardScanSuggestions(): void {
    this.showScanSheet = false;
    this.toast('请手动填写物资信息');
  }

  async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    // 数量归一化：支持 "500g" 混合输入自动拆分
    const normalizedQty = normalizeQuantityUnit(this.quantityStr, this.unit);
    const qtyNumber = Number(normalizedQty.quantity);
    // 日期口径：direct = 包装只印到期日；shelf = 生产日期+保质期推算
    const direct = this.dateMode === DateEntryMode.DIRECT;
    // 保质期：月数模式或天数模式（direct 口径下不参与）
    const months = !direct && this.shelfLifeMode === 'months' ? parseNonNegativeInteger(this.shelfLifeMonthsStr) : null;
    const days = !direct && this.shelfLifeMode === 'months' ? 365 * (months ?? 1) : Number(this.shelfLifeStr);

    if (this.name.trim().length === 0) {
      this.errorMsg = '请输入物资名称';
      return;
    }
    if (normalizedQty.quantity === '' || Number.isNaN(qtyNumber) || qtyNumber <= 0) {
      this.errorMsg = '数量需大于 0';
      return;
    }
    if (direct) {
      if (this.directExpiryDate.length === 0) {
        this.errorMsg = '请选择到期日期';
        return;
      }
    } else if (this.shelfLifeMode === 'months') {
      if (months === null || months < 1) {
        this.errorMsg = '保质期需至少 1 个月';
        return;
      }
    } else {
      if (this.shelfLifeStr === '' || Number.isNaN(days) || days < 1) {
        this.errorMsg = '保质期需至少 1 天';
        return;
      }
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
      quantity: normalizedQty.quantity,
      unit: normalizedQty.unit.length > 0 ? normalizedQty.unit : this.unit,
      location: this.location,
      productionDate: direct ? '' : this.productionDate,
      shelfLifeDays: direct ? 0 : Math.floor(days),
      shelfLifeMonths: direct ? undefined : (months ?? undefined),
      expiryDate: direct
        ? this.directExpiryDate
        : (months !== null && months >= 1
          ? calcExpiryDate(this.productionDate, 0, months)
          : calcExpiryDate(this.productionDate, Math.floor(days))),
      note: this.note.trim(),
      status: this.isEdit ? this.loadedStatus : MaterialStatus.ACTIVE,
      handledType: this.isEdit ? this.loadedHandledType : undefined,
      handledAt: this.isEdit ? this.loadedHandledAt : undefined,
      isDeleted: false,
      createdAt: this.isEdit ? this.loadedCreatedAt : now,
      updatedAt: now,
      barcode: this.barcode.trim().length > 0 ? this.barcode.trim() : undefined,
      customFields: this.customFieldValues
    };
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.db.init(ctx);
      let mergeToast = '';
      if (this.isEdit) {
        await this.db.update(material);
      } else {
        // 同批次并条：同名+同位置+同到期日+同单位的在库记录已存在 → 数量求和，不另起新条
        // （编辑保存不并入：编辑语义是改这条本身，1:1 落库）
        const twin = await this.db.findActiveBatchMatch(material);
        const sum = twin ? batchQuantitySum(twin.quantity, material.quantity) : null;
        if (twin && sum !== null) {
          twin.quantity = sum;
          twin.updatedAt = now;
          // 并条只补空位，不覆盖既有信息（新填的备注/条码/自定义字段仅在原记录为空时带上）
          if (twin.note.length === 0 && material.note.length > 0) {
            twin.note = material.note;
          }
          if ((!twin.barcode || twin.barcode.length === 0) && material.barcode) {
            twin.barcode = material.barcode;
          }
          if ((!twin.customFields || Object.keys(twin.customFields).length === 0)
            && material.customFields && Object.keys(material.customFields).length > 0) {
            twin.customFields = material.customFields;
          }
          await this.db.update(twin);
          mergeToast = `已并入现有记录，数量合并为 ${formatQuantityUnit(sum, material.unit, '')}`;
        } else {
          await this.db.insert(material);
        }
      }
      try {
        await ReminderService.getInstance().syncDailyReminder(ctx);
      } catch (e) {
        console.error(`sync reminder failed: ${(e as BusinessError).message}`);
      }
      const viaBarcode = this.barcode.trim().length > 0;
      UsageService.getInstance().logItemAdded(
        this.name.trim(),
        viaBarcode ? 'barcode' : (this.suggestionApplied ? 'suggestion' : 'manual'),
        this.isEdit,
        Date.now() - this.pageOpenAt,
        material.shelfLifeDays,
        this.shelfLifeMode === 'months');
      this.suggestionApplied = false;
      this.toast(this.isEdit ? '已保存' : (mergeToast.length > 0 ? mergeToast : '已添加'));
      this.getUIContext().getRouter().back();
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
        HardShadowBox({boxWidth: Theme.iconBtnSize, boxHeight: Theme.iconBtnSize}) {

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([Theme.textPrimary])
          }
          .backgroundColor(Theme.cardBg)
          .width(Theme.iconBtnSize)
          .height(Theme.iconBtnSize)
          .border(Theme.borderThin)
          .borderRadius(Theme.iconBtnRadius)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        }

        Text(this.isEdit ? '编辑物资' : '新增物资')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.elementGap })

        Blank()

        if (this.saving) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(Theme.yellowDark)
            .margin({ right: Theme.smallGap })
        }

        Stack() {
          Row()
            .height(Theme.primaryBtnHeight)
            .constraintSize({ minWidth: 88 })
            .backgroundColor(Theme.ink)
            .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

          Button(this.isEdit ? '保存' : '添加', { type: ButtonType.Normal, stateEffect: true })
            .fontSize(Theme.textSubhead)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
            .backgroundColor(Theme.yellowDark)
            .border(Theme.borderThin)
            .borderRadius(Theme.buttonRadius)
            .height(Theme.primaryBtnHeight)
            .padding({ left: 20, right: 20 })
            .enabled(!this.saving)
            .onClick(() => {
              this.save();
            })
        }
        .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding - 4,
        right: Theme.pagePadding,
        top: 12,
        bottom: 12
      })

      Scroll() {
        Column({ space: Theme.cardGap }) {
          if (this.errorMsg !== '') {
            HardShadowCard({shadowMode: 0}) {

              Row({ space: Theme.smallGap }) {
                Column()
                  .width(6)
                  .height('100%')
                  .backgroundColor(Theme.danger)

                Row({ space: Theme.smallGap }) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(18)
                    .fontColor([Theme.danger])
                  Text(this.errorMsg)
                    .fontSize(Theme.textCaption)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.danger)
                    .layoutWeight(1)
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding(Theme.cardPadding)
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
              .borderRadius(Theme.cardRadius)
            }
          }

          Row({ space: Theme.elementGap }) {
            this.actionCapsule(
              $r('sys.symbol.barcode_viewfinder'),
              '扫码快填',
              Theme.yellowDark,
              Theme.textWhite,
              () => this.handleScanBarcode()
            )
          }
          .width('100%')

          HardShadowCard({shadowMode: 0}) {

            Column({ space: Theme.elementGap }) {
              this.sectionTitle('基本信息', Theme.yellowDark)

              this.fieldLabel('物资名称 *')
              HardShadowCard({shadowMode: 0}) {
                TextInput({ text: this.name, placeholder: '如：牛奶、感冒灵、洗面奶' })
                  .fontSize(Theme.textBody)
                  .fontColor(Theme.textPrimary)
                  .placeholderColor(Theme.textTertiary)
                  .backgroundColor(Theme.inputBg)
                  .border(Theme.borderThin)
                  .borderRadius(Theme.inputRadius)
                  .height(48)
                  .onChange((v: string) => {
                    this.name = v;
                    this.lookupNameCandidates(v);
                  })
              }

              if (this.nameCandidates.length > 0) {
                Column({ space: Theme.tinyGap }) {
                  ForEach(this.nameCandidates, (m: Material) => {
                    Row({ space: Theme.smallGap }) {
                      Column({ space: 2 }) {
                        Text(m.name)
                          .fontSize(Theme.textCaption)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Theme.textPrimary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(this.suggestionSummary(m))
                          .fontSize(Theme.textCaption)
                          .fontColor(Theme.textSecondary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text('填入')
                        .fontSize(Theme.textCaption)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.textWhite)
                        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                        .backgroundColor(Theme.yellowDark)
                        .border(Theme.borderThin)
                        .onClick(() => {
                          this.applyNameCandidate(m);
                        })
                    }
                    .width('100%')
                    .padding({ left: Theme.cardPadding, right: Theme.cardPadding, top: 10, bottom: 10 })
                    .backgroundColor(Theme.nearSoft)
                    .border(Theme.borderThin)
                    .alignItems(VerticalAlign.Center)
                    .onClick(() => {
                      this.applyNameCandidate(m);
                    })
                  }, (m: Material) => m.id.toString())
                }
                .width('100%')
              }

              if (this.barcode.trim().length > 0) {
                this.fieldLabel('条形码')
                HardShadowCard({shadowMode: 0}) {
                  Row() {
                    SymbolGlyph($r('sys.symbol.barcode_viewfinder'))
                      .fontSize(18)
                      .fontColor([Theme.yellowDark])
                      .margin({ right: Theme.smallGap })
                    Text(this.barcode)
                      .fontSize(Theme.textSubhead)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.textPrimary)
                      .layoutWeight(1)
                    Text('清除')
                      .fontSize(Theme.textCaption)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.danger)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .border(Theme.borderThin)
                      .borderRadius(Theme.buttonRadius)
                      .onClick(() => {
                        this.barcode = '';
                      })
                  }
                  .width('100%')
                  .padding(Theme.cardPadding)
                  .backgroundColor(Theme.inputBg)
                  .border(Theme.borderThin)
                  .borderRadius(Theme.inputRadius)
                }
              }

              this.fieldLabel('分类')
              ChipGroup({ options: this.categories, selected: this.category, onSelect: (v: string) => {
                this.category = v;
              } })

              this.fieldLabel('存放位置')
              ChipGroup({ options: this.locations, selected: this.location, onSelect: (v: string) => {
                this.location = v;
              } })

              this.fieldLabel('数量 *（支持 500g 混合输入）')
              HardShadowCard({shadowMode: 0}) {
                TextInput({ text: this.quantityStr, placeholder: '如：2 或 500g' })
                  .fontSize(Theme.textBody)
                  .fontColor(Theme.textPrimary)
                  .placeholderColor(Theme.textTertiary)
                  .backgroundColor(Theme.inputBg)
                  .border(Theme.borderThin)
                  .borderRadius(Theme.inputRadius)
                  .height(48)
                  .onChange((v: string) => {
                    this.quantityStr = v;
                  })
              }
              ChipGroup({ options: this.units, selected: this.unit, onSelect: (v: string) => {
                this.unit = v;
              } })
            }
            .width('100%')
            .padding(Theme.cardPadding)
            .backgroundColor(Theme.cardBg)
            .border(Theme.borderThin)
            .borderRadius(Theme.cardRadius)
            .alignItems(HorizontalAlign.Start)
          }

          HardShadowCard({shadowMode: 0}) {

            Column({ space: Theme.elementGap }) {
              this.sectionTitle('日期与保质期', Theme.near)

              // ── 日期口径切换：按保质期算（生产日期+保质期）/ 直接填到期日（包装只印到期日）──
              Row({ space: Theme.smallGap }) {
                Stack() {
                  Column()
                    .height(34)
                    .backgroundColor(Theme.ink)
                    .margin({ left: 3, top: 3 })
                  Text('按保质期算')
                    .fontSize(Theme.textSmall)
                    .fontWeight(this.dateMode === DateEntryMode.SHELF ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.dateMode === DateEntryMode.SHELF ? Theme.textWhite : Theme.textPrimary)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .backgroundColor(this.dateMode === DateEntryMode.SHELF ? Theme.yellowDark : Theme.cardBg)
                    .border(Theme.borderThin)
                    .onClick(() => {
                      this.dateMode = DateEntryMode.SHELF;
                    })
                }
                .padding({ right: 3, bottom: 3 })

                Stack() {
                  Column()
                    .height(34)
                    .backgroundColor(Theme.ink)
                    .margin({ left: 3, top: 3 })
                  Text('直接填到期日')
                    .fontSize(Theme.textSmall)
                    .fontWeight(this.dateMode === DateEntryMode.DIRECT ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.dateMode === DateEntryMode.DIRECT ? Theme.textWhite : Theme.textPrimary)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .backgroundColor(this.dateMode === DateEntryMode.DIRECT ? Theme.yellowDark : Theme.cardBg)
                    .border(Theme.borderThin)
                    .onClick(() => {
                      this.dateMode = DateEntryMode.DIRECT;
                    })
                }
                .padding({ right: 3, bottom: 3 })
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)

              if (this.dateMode === DateEntryMode.SHELF) {
              DateFieldRow({
                label: '生产日期 *',
                value: this.productionDate,
                onPick: () => this.pickProductionDate()
              })

              // ── 保质期模式切换：天数 / 月数（包装常标月数，月末自动 clamp）──
              Row({ space: Theme.smallGap }) {
                Stack() {
                  Column()
                    .height(34)
                    .backgroundColor(Theme.ink)
                    .margin({ left: 3, top: 3 })
                  Text('按天数')
                    .fontSize(Theme.textSmall)
                    .fontWeight(this.shelfLifeMode === 'days' ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.shelfLifeMode === 'days' ? Theme.textWhite : Theme.textPrimary)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .backgroundColor(this.shelfLifeMode === 'days' ? Theme.yellowDark : Theme.cardBg)
                    .border(Theme.borderThin)
                    .onClick(() => {
                      this.shelfLifeMode = 'days';
                    })
                }
                .padding({ right: 3, bottom: 3 })

                Stack() {
                  Column()
                    .height(34)
                    .backgroundColor(Theme.ink)
                    .margin({ left: 3, top: 3 })
                  Text('按月数')
                    .fontSize(Theme.textSmall)
                    .fontWeight(this.shelfLifeMode === 'months' ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.shelfLifeMode === 'months' ? Theme.textWhite : Theme.textPrimary)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .backgroundColor(this.shelfLifeMode === 'months' ? Theme.yellowDark : Theme.cardBg)
                    .border(Theme.borderThin)
                    .onClick(() => {
                      this.shelfLifeMode = 'months';
                      if (this.shelfLifeMonthsStr.length === 0) {
                        this.shelfLifeMonthsStr = '1';
                      }
                    })
                }
                .padding({ right: 3, bottom: 3 })
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)

              if (this.shelfLifeMode === 'days') {
                this.fieldLabel('保质期（天）*')
                HardShadowCard({shadowMode: 0}) {
                  TextInput({ text: this.shelfLifeStr, placeholder: '天数' })
                    .type(InputType.Number)
                    .fontSize(Theme.textBody)
                    .fontColor(Theme.textPrimary)
                    .placeholderColor(Theme.textTertiary)
                    .backgroundColor(Theme.inputBg)
                    .border(Theme.borderThin)
                    .borderRadius(Theme.inputRadius)
                    .height(48)
                    .onChange((v: string) => {
                      this.shelfLifeStr = v;
                    })
                }
                ChipGroup({ options: this.presetLabels(), selected: `${this.shelfLifeStr}天`, onSelect: (v: string) => {
                  this.shelfLifeStr = v.replace('天', '');
                } })
              } else {
                this.fieldLabel('保质期（月）*')
                HardShadowCard({shadowMode: 0}) {
                  TextInput({ text: this.shelfLifeMonthsStr, placeholder: '月数（如 12）' })
                    .type(InputType.Number)
                    .fontSize(Theme.textBody)
                    .fontColor(Theme.textPrimary)
                    .placeholderColor(Theme.textTertiary)
                    .backgroundColor(Theme.inputBg)
                    .border(Theme.borderThin)
                    .borderRadius(Theme.inputRadius)
                    .height(48)
                    .onChange((v: string) => {
                      this.shelfLifeMonthsStr = v;
                    })
                }
                ChipGroup({ options: this.presetMonthLabels(), selected: `${this.shelfLifeMonthsStr}个月`, onSelect: (v: string) => {
                  this.shelfLifeMonthsStr = v.replace('个月', '');
                } })
                Text('按月加法自动处理月末（1/31 + 1个月 = 2/28 或 2/29）')
                  .fontSize(Theme.textCaption)
                  .fontColor(Theme.textTertiary)
              }
              } else {
                DateFieldRow({
                  label: '到期日期 *',
                  value: this.directExpiryDate,
                  caption: '包装上只印「保质期至 / 到期日」时用这个，应用只关心什么时候到期',
                  onPick: () => this.pickDirectExpiryDate()
                })
              }

              HardShadowCard({shadowMode: 0}) {

                Row() {
                  Column({ space: Theme.tinyGap }) {
                    Text(this.dateMode === DateEntryMode.DIRECT ? '到期日' : '预计到期日')
                      .fontSize(Theme.textCaption)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.textWhite)
                      .opacity(0.9)
                    Text(this.expiryPreview())
                      .fontSize(Theme.textHero)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.textWhite)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column()
                    .width(20)
                    .height(20)
                    .backgroundColor(Theme.cardBg)
                    .opacity(0.3)
                }
                .width('100%')
                .padding(Theme.cardPadding)
                .border(Theme.borderThin)
                .borderRadius(Theme.cardRadius)
                .backgroundColor(Theme.safe)
              }
            }
            .width('100%')
            .padding(Theme.cardPadding)
            .backgroundColor(Theme.cardBg)
            .border(Theme.borderThin)
            .borderRadius(Theme.cardRadius)
            .alignItems(HorizontalAlign.Start)
          }

          if (this.customFieldsDefs.length > 0) {
            HardShadowCard({shadowMode: 0}) {

              Column({ space: Theme.elementGap }) {
                this.sectionTitle('扩展信息', Theme.expired)

                ForEach(this.customFieldsDefs, (def: CustomField) => {
                  this.renderCustomFieldInput(def)
                }, (def: CustomField) => def.id)
              }
              .width('100%')
              .padding(Theme.cardPadding)
              .backgroundColor(Theme.cardBg)
              .border(Theme.borderThin)
              .borderRadius(Theme.cardRadius)
              .alignItems(HorizontalAlign.Start)
            }
          }

          HardShadowCard({shadowMode: 0}) {

            Column({ space: Theme.elementGap }) {
              this.sectionTitle('备注', Theme.safe)

              HardShadowCard({shadowMode: 0}) {
                TextArea({ text: this.note, placeholder: '选填，如存放位置、购买渠道等' })
                  .fontSize(Theme.textBody)
                  .fontColor(Theme.textPrimary)
                  .placeholderColor(Theme.textTertiary)
                  .backgroundColor(Theme.inputBg)
                  .border(Theme.borderThin)
                  .borderRadius(Theme.inputRadius)
                  .height(120)
                  .onChange((v: string) => {
                    this.note = v;
                  })
              }
            }
            .width('100%')
            .padding(Theme.cardPadding)
            .backgroundColor(Theme.cardBg)
            .border(Theme.borderThin)
            .borderRadius(Theme.cardRadius)
            .alignItems(HorizontalAlign.Start)
          }

          Column()
            .width('100%')
            .height(20)
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
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.avoidTopVp, bottom: this.avoidBottomVp })
    .backgroundColor(Theme.pageBg)
    .bindSheet($$this.showScanSheet, this.scanSuggestionsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: Theme.sheetBg,
      onDisappear: () => {
        this.showScanSheet = false;
      }
    })
  }

  @Builder
  actionCapsule(symbol: Resource, label: string, bgColor: string, textColor: string, onClick: () => void) {
    Stack() {
      Row()
        .layoutWeight(1)
        .height(Theme.primaryBtnHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: Theme.smallGap }) {
          SymbolGlyph(symbol)
            .fontSize(18)
            .fontColor([textColor])
          Text(label)
            .fontSize(Theme.textSubhead)
            .fontWeight(FontWeight.Bold)
            .fontColor(textColor)
        }
      }
      .layoutWeight(1)
      .height(Theme.primaryBtnHeight)
      .backgroundColor(bgColor)
      .border(Theme.borderThin)
      .borderRadius(Theme.buttonRadius)
      .onClick(onClick)
    }
    .layoutWeight(1)
    .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
  }

  @Builder
  sectionTitle(title: string, accentColor: string) {
    Row({ space: Theme.smallGap }) {
      Column()
        .width(6)
        .height(Theme.textHeadline + 2)
        .backgroundColor(accentColor)

      Text(title)
        .fontSize(Theme.textHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
    }
    .width('100%')
    .margin({ bottom: Theme.tinyGap })
  }

  @Builder
  scanSuggestionsSheet() {
    Column({ space: Theme.elementGap }) {
      Row({ space: Theme.smallGap }) {
        Column()
          .width(6)
          .height(Theme.textHero)
          .backgroundColor(Theme.yellowDark)
        Text('扫码快填')
          .fontSize(Theme.textHeadline)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
      }
      .width('100%')
      .margin({ top: Theme.smallGap })

      Text(`条码 ${this.barcode} 匹配到历史入库记录，选择一条预填表单`)
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textSecondary)

      List({ space: Theme.smallGap }) {
        ForEach(this.scanSuggestions, (m: Material) => {
          ListItem() {
            this.suggestionRow(m)
          }
        }, (m: Material) => m.id.toString())
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)

      HardShadowCard({shadowMode: Theme.primaryBtnHeight}) {

        Button('都不对，手动填写', { type: ButtonType.Normal, stateEffect: true })
          .width('100%')
          .height(Theme.primaryBtnHeight)
          .borderRadius(Theme.buttonRadius)
          .backgroundColor(Theme.cardBg)
          .border(Theme.borderThin)
          .fontSize(Theme.textSubhead)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .onClick(() => {
            this.discardScanSuggestions();
          })
      }
    }
    .width('100%')
    .padding({
      left: Theme.pagePadding,
      right: Theme.pagePadding,
      top: Theme.cardPadding
    })
  }

  @Builder
  suggestionRow(m: Material) {
    HardShadowCard({shadowMode: 0}) {

      Row() {
        Column() {
          Row({ space: Theme.smallGap }) {
            Text(m.name)
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (m.isDeleted) {
              // 回收站模板兜底标记：该条码已无在库行，此候选来自删除历史（仅预填，不复活）
              Text('已删')
                .fontSize(Theme.textTiny)
                .fontColor(Theme.textTertiary)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .border({ width: 1, color: Theme.textTertiary })
            }
          }
          .width('100%')
          Text(m.productionDate.length === 0
            ? `${m.category} · ${m.quantity}${m.unit} · 到期日 ${m.expiryDate}`
            : `${m.category} · ${m.quantity}${m.unit} · 保质期${m.shelfLifeDays}天`)
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)
            .margin({ top: Theme.tinyGap })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('最近入库')
            .fontSize(Theme.textTiny)
            .fontColor(Theme.textTertiary)
            .fontWeight(FontWeight.Medium)
          Text(m.createdAt)
            .fontSize(Theme.textCaption)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textSecondary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.inputBg)
      .border(Theme.borderThin)
      .borderRadius(Theme.inputRadius)
      .onClick(() => {
        this.applyScanSuggestion(m);
      })
    }
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(Theme.textCaption)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textSecondary)
      .margin({ bottom: Theme.tinyGap })
  }

  /* chipGroup 已上移为文件级 ChipGroup 组件（@Prop 响应式），见文件头部 */

  @Builder
  renderCustomFieldInput(def: CustomField) {
    if (def.type === 'text') {
      this.fieldLabel(def.name)
      HardShadowCard({shadowMode: 0}) {
        TextInput({ text: this.customFieldValues[def.id] || '', placeholder: '选填' })
          .fontSize(Theme.textBody)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textTertiary)
          .backgroundColor(Theme.inputBg)
          .border(Theme.borderThin)
          .borderRadius(Theme.inputRadius)
          .height(48)
          .onChange((v: string) => {
            this.updateCustomFieldValue(def.id, v);
          })
      }
    } else if (def.type === 'number') {
      this.fieldLabel(def.name)
      HardShadowCard({shadowMode: 0}) {
        TextInput({ text: this.customFieldValues[def.id] || '', placeholder: '选填（数字）' })
          .type(InputType.Number)
          .fontSize(Theme.textBody)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textTertiary)
          .backgroundColor(Theme.inputBg)
          .border(Theme.borderThin)
          .borderRadius(Theme.inputRadius)
          .height(48)
          .onChange((v: string) => {
            this.updateCustomFieldValue(def.id, v);
          })
      }
    } else if (def.type === 'date') {
      this.fieldLabel(def.name)
      HardShadowCard({shadowMode: 0}) {
        Row() {
          Text(this.customFieldValues[def.id] ? this.customFieldValues[def.id] : `选择${def.name}`)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.customFieldValues[def.id] ? Theme.textPrimary : Theme.textTertiary)
            .layoutWeight(1)
          if (this.customFieldValues[def.id] && this.customFieldValues[def.id].length > 0) {
            Text('清除')
              .fontSize(Theme.textCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.danger)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .border(Theme.borderThin)
              .borderRadius(Theme.buttonRadius)
              .margin({ right: Theme.smallGap })
              .onClick(() => {
                this.updateCustomFieldValue(def.id, '');
              })
          }
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(20)
            .fontColor([Theme.expired])
        }
        .width('100%')
        .padding(Theme.cardPadding)
        .backgroundColor(Theme.inputBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.inputRadius)
        .height(48)
        .onClick(() => {
          this.pickCustomFieldDate(def.id);
        })
      }
    } else if (def.type === 'enum') {
      this.fieldLabel(def.name)
      this.customEnumChipGroup(def.id, def.options || [])
    }
  }

  @Builder
  customEnumChipGroup(fieldId: string, options: string[]) {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(options, (opt: string) => {
        Stack() {
          Row()
            .backgroundColor(Theme.ink)
            .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })

          Text(opt)
            .fontSize(Theme.textCaption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.customFieldValues[fieldId] === opt ? Theme.textWhite : Theme.textPrimary)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(Theme.chipRadius)
            .backgroundColor(this.customFieldValues[fieldId] === opt ? Theme.yellowDark : Theme.inputBg)
            .border(Theme.borderThin)
            .onClick(() => {
              this.selectCustomEnumOption(fieldId, opt);
            })
        }
        .margin({ right: Theme.smallGap + Theme.hardShadowOffset, bottom: Theme.smallGap + Theme.hardShadowOffset })
      }, (opt: string) => opt)
    }
    .width('100%')
  }
}
