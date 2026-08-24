/**
 * 自定义字段管理页 —— 清新自然风格。
 * 支持新建、编辑（改名/选项，禁改类型）、删除（二次确认）、排序（上移/下移）。
 */
import { router, promptAction } from '@kit.ArkUI';
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
            type: existing.type, // 不允许改类型
            options: existing.type === 'enum' ? this.enumOptions : undefined,
            order: existing.order,
            createdAt: existing.createdAt
          };
          await this.db.updateCustomField(updated);
          promptAction.showToast({ message: '已更新字段' });
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
        promptAction.showToast({ message: '已创建字段' });
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
      promptAction.showToast({ message: '已删除字段' });
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

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
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

          Text('自定义字段管理')
            .fontSize(Theme.textTitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)
            .margin({ left: Theme.smallGap })

          Blank()

          Button('新建字段')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(Theme.brand)
            .borderRadius(20)
            .height(36)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
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
            LoadingProgress().width(40).height(40).color(Theme.brand)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.customFields.length === 0) {
          this.emptyState()
        } else {
          List({ space: Theme.elementGap }) {
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
    .bindSheet($$this.showEditSheet, this.fieldEditSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: Theme.cardBg,
      onDisappear: () => {
        this.showEditSheet = false;
      }
    })
  }

  @Builder
  emptyState() {
    Column({ space: Theme.elementGap }) {
      Column() {
        SymbolGlyph($r('sys.symbol.list_bullet_rectangle'))
          .fontSize(48)
          .fontColor([Theme.brand])
          .opacity(0.4)
      }
      .width(80)
      .height(80)
      .borderRadius(40)
      .backgroundColor(Theme.brandSoft)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: Theme.smallGap })

      Text('暂无自定义字段')
        .fontSize(Theme.textBody)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary)
      Text('创建自定义字段后，可在录入物资时添加个性化信息（如存放位置、品牌等）')
        .fontSize(Theme.textCaption)
        .fontColor(Theme.textTertiary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Button('+ 新建自定义字段')
        .fontSize(Theme.textSubhead)
        .fontColor(Color.White)
        .backgroundColor(Theme.brand)
        .borderRadius(20)
        .height(42)
        .padding({ left: 24, right: 24 })
        .margin({ top: 16 })
        .onClick(() => {
          this.openCreateSheet();
        })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  fieldCard(f: CustomField, index: number) {
    Column({ space: Theme.smallGap }) {
      Row() {
        Row({ space: Theme.smallGap }) {
          Text(f.name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)

          Text(getFieldTypeName(f.type))
            .fontSize(Theme.textTiny)
            .fontColor(Theme.brand)
            .backgroundColor(Theme.brandSoft)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
        }
        .layoutWeight(1)

        Row({ space: Theme.tinyGap }) {
          // 上移
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_up'))
              .fontSize(14)
              .fontColor([index > 0 ? Theme.textSecondary : Theme.border])
          }
          .backgroundColor(Theme.inputBg)
          .borderRadius(8)
          .width(32)
          .height(32)
          .enabled(index > 0)
          .onClick(() => {
            this.moveFieldUp(index);
          })

          // 下移
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(14)
              .fontColor([index < this.customFields.length - 1 ? Theme.textSecondary : Theme.border])
          }
          .backgroundColor(Theme.inputBg)
          .borderRadius(8)
          .width(32)
          .height(32)
          .enabled(index < this.customFields.length - 1)
          .onClick(() => {
            this.moveFieldDown(index);
          })

          // 编辑
          Button('编辑')
            .fontSize(13)
            .fontColor(Theme.brand)
            .backgroundColor(Theme.brandSoft)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.openEditSheet(f);
            })

          // 删除
          Button('删除')
            .fontSize(13)
            .fontColor(Theme.danger)
            .backgroundColor(Theme.dangerSoft)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
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
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.cardBg)
    .shadow(Theme.shadowStyle)
  }

  @Builder
  fieldEditSheet() {
    Column({ space: Theme.elementGap }) {
      Text(this.isEditing ? '编辑自定义字段' : '新建自定义字段')
        .fontSize(Theme.textHeadline)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textPrimary)
        .width('100%')
        .padding({ top: 6, bottom: 2 })

      if (this.sheetErrorMsg !== '') {
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
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.dangerSoft)
      }

      Column({ space: Theme.tinyGap }) {
        Text('字段名称 *')
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)
        TextInput({ text: this.inputName, placeholder: '如：存放位置、品牌、规格' })
          .fontSize(Theme.textBody)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textTertiary)
          .backgroundColor(Theme.inputBg)
          .borderRadius(Theme.inputRadius)
          .onChange((v: string) => {
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
          .padding(Theme.cardPadding)
          .borderRadius(Theme.inputRadius)
          .backgroundColor(Theme.inputBg)
        } else {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(CUSTOM_FIELD_TYPES, (type: CustomFieldType) => {
              Text(getFieldTypeName(type))
                .fontSize(14)
                .fontColor(this.selectedType === type ? Color.White : Theme.textPrimary)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .borderRadius(Theme.chipRadius)
                .backgroundColor(this.selectedType === type ? Theme.brand : Theme.inputBg)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
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
        Column({ space: Theme.smallGap }) {
          Text('单选选项（至少 2 个选项）*')
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textSecondary)

          Row({ space: Theme.smallGap }) {
            TextInput({ text: this.newOptionInput, placeholder: '输入选项名称，如：冷藏' })
              .fontSize(Theme.textSubhead)
              .fontColor(Theme.textPrimary)
              .placeholderColor(Theme.textTertiary)
              .backgroundColor(Theme.inputBg)
              .borderRadius(Theme.inputRadius)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.newOptionInput = v;
              })

            Button('添加')
              .fontSize(Theme.textCaption)
              .fontColor(Color.White)
              .backgroundColor(Theme.brand)
              .borderRadius(Theme.inputRadius)
              .height(40)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.addEnumOption();
              })
          }
          .width('100%')

          if (this.enumOptions.length > 0) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.enumOptions, (opt: string, idx: number) => {
                Row({ space: Theme.tinyGap }) {
                  Text(opt)
                    .fontSize(13)
                    .fontColor(Theme.textPrimary)
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(12)
                    .fontColor([Theme.textTertiary])
                    .padding({ left: 2, right: 2 })
                    .onClick(() => {
                      this.removeEnumOption(idx);
                    })
                }
                .padding({ left: 12, right: 8, top: 6, bottom: 6 })
                .borderRadius(16)
                .backgroundColor(Theme.inputBg)
                .margin({ right: 8, bottom: 8 })
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
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor(Theme.inputBg)
          .fontColor(Theme.textPrimary)
          .fontSize(Theme.textSubhead)
          .onClick(() => {
            this.showEditSheet = false;
          })

        Button(this.isEditing ? '保存' : '创建')
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor(Theme.brand)
          .fontColor(Color.White)
          .fontSize(Theme.textSubhead)
          .onClick(() => {
            this.saveField();
          })
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
