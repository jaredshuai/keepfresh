/**
 * 自定义字段管理页 —— 包豪斯（Bauhaus）设计风格。
 * 支持新建、编辑（改名/选项，禁改类型）、删除（二次确认）、排序（上移/下移）。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  CustomField,
  CustomFieldType,
  CUSTOM_FIELD_TYPES,
  getFieldTypeName,
  validateCustomFieldName,
  validateEnumOptions,
  generateCustomFieldId
} from '../model/CustomField';
import { MaterialDb } from '../db/MaterialDb';
import { todayStr } from '../common/DateUtils';
import { Theme } from '../common/Theme';

@Entry
@Component
struct CustomFieldManager {
  @State customFields: CustomField[] = [];
  @State loading: boolean = true;
  @State showEditSheet: boolean = false;
  @State isEditing: boolean = false;
  @State editingId: string = '';
  @State inputName: string = '';
  @State selectedType: CustomFieldType = 'text';
  @State enumOptions: string[] = [];
  @State newOptionInput: string = '';
  @State sheetErrorMsg: string = '';
  private db: MaterialDb = MaterialDb.getInstance();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.db.init(ctx)
      .then(() => {
        return this.loadFields();
      })
      .catch((e: BusinessError) => {
        console.error(`init db failed: ${e.message}`);
        this.loading = false;
      });
  }

  private async loadFields(): Promise<void> {
    try {
      this.customFields = await this.db.listCustomFields();
    } catch (e) {
      console.error(`load custom fields failed: ${(e as BusinessError).message}`);
    } finally {
      this.loading = false;
    }
  }

  private openCreateSheet(): void {
    this.isEditing = false;
    this.editingId = '';
    this.inputName = '';
    this.selectedType = 'text';
    this.enumOptions = [];
    this.newOptionInput = '';
    this.sheetErrorMsg = '';
    this.showEditSheet = true;
  }

  private openEditSheet(field: CustomField): void {
    this.isEditing = true;
    this.editingId = field.id;
    this.inputName = field.name;
    this.selectedType = field.type;
    this.enumOptions = field.options ? [...field.options] : [];
    this.newOptionInput = '';
    this.sheetErrorMsg = '';
    this.showEditSheet = true;
  }

  private addEnumOption(): void {
    const opt = this.newOptionInput.trim();
    if (opt.length === 0) {
      this.sheetErrorMsg = '请输入选项名称';
      return;
    }
    if (this.enumOptions.includes(opt)) {
      this.sheetErrorMsg = `选项「${opt}」已存在`;
      return;
    }
    this.enumOptions.push(opt);
    this.newOptionInput = '';
    this.sheetErrorMsg = '';
  }

  private removeEnumOption(index: number): void {
    this.enumOptions.splice(index, 1);
  }

  private async saveField(): Promise<void> {
    const nameErr = validateCustomFieldName(this.inputName, this.customFields, this.isEditing ? this.editingId : undefined);
    if (nameErr) {
      this.sheetErrorMsg = nameErr;
      return;
    }

    if (this.selectedType === 'enum') {
      const enumErr = validateEnumOptions(this.enumOptions);
      if (enumErr) {
        this.sheetErrorMsg = enumErr;
        return;
      }
    }

    this.sheetErrorMsg = '';

    try {
      if (this.isEditing) {
        const existing = this.customFields.find((f: CustomField) => f.id === this.editingId);
        if (existing) {
          const updated: CustomField = {
            id: existing.id,
            name: this.inputName.trim(),
            type: existing.type,
            options: existing.type === 'enum' ? this.enumOptions : undefined,
            order: existing.order,
            createdAt: existing.createdAt
          };
          await this.db.updateCustomField(updated);
          this.getUIContext().getPromptAction().showToast({ message: '已更新字段' });
        }
      } else {
        const newField: CustomField = {
          id: generateCustomFieldId(),
          name: this.inputName.trim(),
          type: this.selectedType,
          options: this.selectedType === 'enum' ? this.enumOptions : undefined,
          order: this.customFields.length,
          createdAt: todayStr()
        };
        await this.db.insertCustomField(newField);
        this.getUIContext().getPromptAction().showToast({ message: '已创建字段' });
      }
      this.showEditSheet = false;
      await this.loadFields();
    } catch (e) {
      const err = e as BusinessError;
      this.sheetErrorMsg = `保存失败：${err.message}`;
      console.error(`save custom field failed: ${err.message}`);
    }
  }

  private confirmDelete(field: CustomField): void {
    this.getUIContext().showAlertDialog({
      title: '删除自定义字段',
      message: `确定删除字段「${field.name}」吗？已有物资中的该字段数据将保留但不再显示。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.danger,
        action: async () => {
          await this.doDelete(field.id);
        }
      }
    });
  }

  private async doDelete(id: string): Promise<void> {
    try {
      await this.db.removeCustomField(id);
      await this.loadFields();
      this.getUIContext().getPromptAction().showToast({ message: '已删除字段' });
    } catch (e) {
      console.error(`delete custom field failed: ${(e as BusinessError).message}`);
    }
  }

  private async moveFieldUp(index: number): Promise<void> {
    if (index <= 0 || index >= this.customFields.length) {
      return;
    }
    const list = [...this.customFields];
    const temp = list[index];
    list[index] = list[index - 1];
    list[index - 1] = temp;
    await this.db.updateCustomFieldsOrder(list);
    await this.loadFields();
  }

  private async moveFieldDown(index: number): Promise<void> {
    if (index < 0 || index >= this.customFields.length - 1) {
      return;
    }
    const list = [...this.customFields];
    const temp = list[index];
    list[index] = list[index + 1];
    list[index + 1] = temp;
    await this.db.updateCustomFieldsOrder(list);
    await this.loadFields();
  }

  @Builder
  bauhausIconBtn(iconResource: Resource, onClickAction: () => void, enabled: boolean = true) {
    Stack() {
      Column()
        .width(40)
        .height(40)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })
        .opacity(enabled ? 1 : 0.3)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph(iconResource)
          .fontSize(24)
          .fontColor([enabled ? Theme.textPrimary : Theme.textTertiary])
      }
      .backgroundColor(Theme.cardBg)
      .width(40)
      .height(40)
      .border(Theme.borderThin)
      .borderRadius(Theme.iconBtnRadius)
      .enabled(enabled)
      .onClick(() => {
        if (enabled) {
          onClickAction();
        }
      })
    }
    .width(44)
    .height(44)
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  bauhausPrimaryBtn(label: string, btnHeight: number, onClickAction: () => void) {
    Stack() {
      Column()
        .height(btnHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Button(label, { type: ButtonType.Normal, stateEffect: true })
        .fontSize(Theme.textSubhead)
        .fontColor(Theme.textWhite)
        .backgroundColor(Theme.yellowDark)
        .border(Theme.borderThin)
        .borderRadius(Theme.buttonRadius)
        .height(btnHeight)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          onClickAction();
        })
    }
    .height(btnHeight + 4)
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  bauhausSecondaryBtn(label: string, btnHeight: number, onClickAction: () => void) {
    Stack() {
      Column()
        .height(btnHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Button(label, { type: ButtonType.Normal, stateEffect: true })
        .fontSize(Theme.textSubhead)
        .fontColor(Theme.textPrimary)
        .backgroundColor(Theme.cardBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.buttonRadius)
        .height(btnHeight)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          onClickAction();
        })
    }
    .height(btnHeight + 4)
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  bauhausDangerBtn(label: string, btnHeight: number, onClickAction: () => void) {
    Stack() {
      Column()
        .height(btnHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Button(label, { type: ButtonType.Normal, stateEffect: true })
        .fontSize(Theme.textSubhead)
        .fontColor(Theme.danger)
        .backgroundColor(Theme.cardBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.buttonRadius)
        .height(btnHeight)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          onClickAction();
        })
    }
    .height(btnHeight + 4)
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  bauhausSmallIconBtn(iconResource: Resource, btnSize: number, isPrimary: boolean, enabled: boolean, onClickAction: () => void) {
    Stack() {
      Column()
        .width(btnSize)
        .height(btnSize)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })
        .opacity(enabled ? 1 : 0.3)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph(iconResource)
          .fontSize(14)
          .fontColor([isPrimary ? Theme.textWhite : (enabled ? Theme.textPrimary : Theme.textTertiary)])
      }
      .backgroundColor(isPrimary ? Theme.yellowDark : Theme.cardBg)
      .width(btnSize)
      .height(btnSize)
      .border(Theme.borderThin)
      .borderRadius(Theme.iconBtnRadius)
      .enabled(enabled)
      .onClick(() => {
        if (enabled) {
          onClickAction();
        }
      })
    }
    .width(btnSize + 4)
    .height(btnSize + 4)
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  bauhausSmallTextBtn(label: string, btnHeight: number, btnKind: string, onClickAction: () => void) {
    Stack() {
      Column()
        .height(btnHeight)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Button(label, { type: ButtonType.Normal, stateEffect: true })
        .fontSize(13)
        .fontColor(btnKind === 'primary' ? Theme.textWhite : (btnKind === 'danger' ? Theme.danger : Theme.textPrimary))
        .backgroundColor(btnKind === 'primary' ? Theme.yellowDark : Theme.cardBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.buttonRadius)
        .height(btnHeight)
        .padding({ left: 10, right: 10 })
        .onClick(() => {
          onClickAction();
        })
    }
    .height(btnHeight + 4)
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  bauhausChip(label: string, isSelected: boolean, onClickAction: () => void) {
    Stack() {
      Column()
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Text(label)
        .fontSize(14)
        .fontColor(isSelected ? Theme.textWhite : Theme.textPrimary)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(isSelected ? Theme.yellowDark : Theme.cardBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.chipRadius)
        .onClick(() => {
          onClickAction();
        })
    }
    .padding({ right: 4, bottom: 4 })
    .margin({ right: 8, bottom: 8 })
  }

  @Builder
  bauhausEnumChip(label: string, onRemove: () => void) {
    Stack() {
      Column()
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Row({ space: Theme.tinyGap }) {
        Text(label)
          .fontSize(13)
          .fontColor(Theme.textPrimary)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(12)
          .fontColor([Theme.textTertiary])
          .padding({ left: 2, right: 2 })
          .onClick(() => {
            onRemove();
          })
      }
      .padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .borderRadius(Theme.chipRadius)
    }
    .padding({ right: 4, bottom: 4 })
    .margin({ right: 8, bottom: 8 })
  }

  @Builder
  bauhausInput(placeholder: string, textContent: string, onChangeAction: (v: string) => void) {
    Stack() {
      Column()
        .height(44)
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      TextInput({ text: textContent, placeholder: placeholder })
        .fontSize(Theme.textBody)
        .fontColor(Theme.textPrimary)
        .placeholderColor(Theme.textTertiary)
        .backgroundColor(Theme.inputBg)
        .border(Theme.borderThin)
        .borderRadius(Theme.inputRadius)
        .height(44)
        .padding({ left: 12, right: 12 })
        .onChange((v: string) => {
          onChangeAction(v);
        })
    }
    .height(48)
    .padding({ right: 4, bottom: 4 })
  }

  build() {
    Column() {
      Row() {
        this.bauhausIconBtn($r('sys.symbol.chevron_left'), () => {
          this.getUIContext().getRouter().back();
        }, true)

        Text('自定义字段管理')
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.smallGap })

        Blank()

        this.bauhausPrimaryBtn('新建字段', 36, () => {
          this.openCreateSheet();
        })
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
          LoadingProgress().width(40).height(40).color(Theme.yellowDark)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.customFields.length === 0) {
        this.emptyState()
      } else {
        List({ space: Theme.elementGap + 8 }) {
          ForEach(this.customFields, (f: CustomField, index: number) => {
            ListItem() {
              this.fieldCard(f, index)
            }
          }, (f: CustomField) => `${f.id}_${f.order}_${f.name}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({
          left: Theme.pagePadding,
          right: Theme.pagePadding,
          top: 8,
          bottom: 30
        })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
    .bindSheet($$this.showEditSheet, this.fieldEditSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: Theme.sheetBg,
      onDisappear: () => {
        this.showEditSheet = false;
      }
    })
  }

  @Builder
  emptyState() {
    Column({ space: Theme.elementGap }) {
      Row({ space: 24 }) {
        Circle({ width: 36, height: 36 })
          .fill(Theme.expired)
          .stroke(Theme.ink)
          .strokeWidth(2)

        Canvas() {
          Path()
            .commands(`M 18 0 L 36 36 L 0 36 Z`)
            .fill(Theme.near)
            .stroke(Theme.ink)
            .strokeWidth(2)
        }
        .width(36)
        .height(36)

        Rect({ width: 36, height: 36 })
          .fill(Theme.safe)
          .stroke(Theme.ink)
          .strokeWidth(2)
      }
      .margin({ bottom: Theme.smallGap + 8 })

      Text('暂无自定义字段')
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary)
      Text('创建自定义字段后，可在录入物资时添加个性化信息（如存放位置、品牌等）')
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Stack() {
        this.bauhausPrimaryBtn('+ 新建自定义字段', 42, () => {
          this.openCreateSheet();
        })
      }
      .margin({ top: 16 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  fieldCard(f: CustomField, index: number) {
    Stack() {
      Column()
        .width('100%')
        .backgroundColor(Theme.ink)
        .margin({ left: 4, top: 4 })

      Column({ space: Theme.smallGap }) {
        Row() {
          Row({ space: Theme.smallGap }) {
            Text(f.name)
              .fontSize(Theme.textBody)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)

            Stack() {
              Column()
                .backgroundColor(Theme.ink)
                .margin({ left: 3, top: 3 })
              Text(getFieldTypeName(f.type))
                .fontSize(Theme.textTiny)
                .fontColor(Theme.textWhite)
                .backgroundColor(Theme.yellowDark)
                .border({ width: 2, color: Theme.ink })
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            }
            .padding({ right: 3, bottom: 3 })
          }
          .layoutWeight(1)

          Row({ space: 2 }) {
            this.bauhausSmallIconBtn($r('sys.symbol.arrow_up'), 32, false, index > 0, () => {
              this.moveFieldUp(index);
            })

            this.bauhausSmallIconBtn($r('sys.symbol.arrow_down'), 32, false, index < this.customFields.length - 1, () => {
              this.moveFieldDown(index);
            })

            this.bauhausSmallTextBtn('编辑', 32, 'primary', () => {
              this.openEditSheet(f);
            })

            this.bauhausSmallTextBtn('删除', 32, 'danger', () => {
              this.confirmDelete(f);
            })
          }
        }
        .width('100%')

        if (f.type === 'enum' && f.options && f.options.length > 0) {
          Row() {
            Text(`选项：${f.options.join(' · ')}`)
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textSecondary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ top: 4 })
        }
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
    }
    .width('100%')
    .padding({ right: 4, bottom: 4 })
  }

  @Builder
  fieldEditSheet() {
    Column({ space: Theme.elementGap + 4 }) {
      Text(this.isEditing ? '编辑自定义字段' : '新建自定义字段')
        .fontSize(Theme.textHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
        .width('100%')
        .padding({ top: 6, bottom: 2 })

      if (this.sheetErrorMsg !== '') {
        Stack() {
          Column()
            .width('100%')
            .backgroundColor(Theme.ink)
            .margin({ left: 4, top: 4 })

          Row({ space: Theme.smallGap }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(16)
              .fontColor([Theme.danger])
            Text(this.sheetErrorMsg)
              .fontSize(Theme.textCaption)
              .fontColor(Theme.danger)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(Theme.cardPadding)
          .backgroundColor(Theme.dangerSoft)
          .border(Theme.borderThin)
        }
        .width('100%')
        .padding({ right: 4, bottom: 4 })
      }

      Column({ space: Theme.tinyGap }) {
        Text('字段名称 *')
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)
        this.bauhausInput('如：存放位置、品牌、规格', this.inputName, (v: string) => {
          this.inputName = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: Theme.tinyGap }) {
        Text(this.isEditing ? '字段类型（创建后不可修改）' : '字段类型 *')
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)

        if (this.isEditing) {
          Stack() {
            Column()
              .width('100%')
              .height(52)
              .backgroundColor(Theme.ink)
              .margin({ left: 4, top: 4 })

            Row() {
              Text(getFieldTypeName(this.selectedType))
                .fontSize(Theme.textSubhead)
                .fontColor(Theme.textPrimary)
                .fontWeight(FontWeight.Medium)
              Blank()
              Text('不可修改')
                .fontSize(Theme.textCaption)
                .fontColor(Theme.textTertiary)
            }
            .width('100%')
            .height(52)
            .padding(Theme.cardPadding)
            .backgroundColor(Theme.inputBg)
            .border(Theme.borderThin)
          }
          .width('100%')
          .padding({ right: 4, bottom: 4 })
        } else {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(CUSTOM_FIELD_TYPES, (type: CustomFieldType) => {
              this.bauhausChip(getFieldTypeName(type), this.selectedType === type, () => {
                this.selectedType = type;
              })
            }, (type: CustomFieldType) => type)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.selectedType === 'enum') {
        Column({ space: Theme.smallGap + 4 }) {
          Text('单选选项（至少 2 个选项）*')
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)

          Row({ space: Theme.smallGap }) {
            Stack() {
              Column()
                .height(44)
                .backgroundColor(Theme.ink)
                .margin({ left: 4, top: 4 })

              TextInput({ text: this.newOptionInput, placeholder: '输入选项名称，如：冷藏' })
                .fontSize(Theme.textSubhead)
                .fontColor(Theme.textPrimary)
                .placeholderColor(Theme.textTertiary)
                .backgroundColor(Theme.inputBg)
                .border(Theme.borderThin)
                .borderRadius(Theme.inputRadius)
                .height(44)
                .padding({ left: 12, right: 12 })
                .onChange((v: string) => {
                  this.newOptionInput = v;
                })
            }
            .layoutWeight(1)
            .height(48)
            .padding({ right: 4, bottom: 4 })

            this.bauhausPrimaryBtn('添加', 40, () => {
              this.addEnumOption();
            })
          }
          .width('100%')

          if (this.enumOptions.length > 0) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.enumOptions, (opt: string, idx: number) => {
                this.bauhausEnumChip(opt, () => {
                  this.removeEnumOption(idx);
                })
              }, (opt: string) => opt)
            }
            .width('100%')
            .padding({ top: 4 })
          } else {
            Text('暂无选项，请在上方的输入框中添加')
              .fontSize(Theme.textCaption)
              .fontColor(Theme.textTertiary)
              .margin({ top: 2 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Row({ space: Theme.elementGap }) {
        Stack() {
          Column()
            .layoutWeight(1)
            .height(48)
            .backgroundColor(Theme.ink)
            .margin({ left: 4, top: 4 })

          Button('取消')
            .layoutWeight(1)
            .height(48)
            .borderRadius(Theme.buttonRadius)
            .backgroundColor(Theme.cardBg)
            .fontColor(Theme.textPrimary)
            .fontSize(Theme.textSubhead)
            .border(Theme.borderThin)
            .onClick(() => {
              this.showEditSheet = false;
            })
        }
        .layoutWeight(1)
        .height(52)
        .padding({ right: 4, bottom: 4 })

        Stack() {
          Column()
            .layoutWeight(1)
            .height(48)
            .backgroundColor(Theme.ink)
            .margin({ left: 4, top: 4 })

          Button(this.isEditing ? '保存' : '创建')
            .layoutWeight(1)
            .height(48)
            .borderRadius(Theme.buttonRadius)
            .backgroundColor(Theme.yellowDark)
            .fontColor(Theme.textWhite)
            .fontSize(Theme.textSubhead)
            .border(Theme.borderThin)
            .onClick(() => {
              this.saveField();
            })
        }
        .layoutWeight(1)
        .height(52)
        .padding({ right: 4, bottom: 4 })
      }
      .width('100%')
      .margin({ top: 12, bottom: 16 })
    }
    .width('100%')
    .padding({
      left: Theme.pagePadding,
      right: Theme.pagePadding,
      top: 12,
      bottom: 12
    })
  }
}
