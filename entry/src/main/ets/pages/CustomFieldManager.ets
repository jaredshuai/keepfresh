/**
 * 自定义字段管理页 —— 鸿蒙官方设计风格。
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

const CLR_BRAND = '#2FA84F';
const CLR_BG = '#F1F3F5';
const CLR_CARD = '#FFFFFF';
const CLR_TEXT = '#182431';
const CLR_TEXT_SUB = '#99182431';
const CLR_TEXT_TIP = '#4D182431';
const CLR_INPUT_BG = '#F1F3F5';
const CLR_DANGER = '#FA2A2D';
const CLR_PREVIEW_BG = '#E8F5EF';
const CLR_BORDER = '#E5E5E5';

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
        fontColor: CLR_DANGER,
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
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([CLR_TEXT])
            .padding({ left: 4, right: 4, top: 6, bottom: 6 })
            .onClick(() => {
              router.back();
            })
          Text('自定义字段管理')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(CLR_TEXT)
            .margin({ left: 4 })
          Blank()
          Button('新建字段')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(CLR_BRAND)
            .borderRadius(20)
            .height(36)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.openCreateSheet();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: 12, bottom: 12 })

        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40).color(CLR_BRAND)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.customFields.length === 0) {
          Column({ space: 12 }) {
            Text('暂无自定义字段')
              .fontSize(16)
              .fontColor(CLR_TEXT_SUB)
            Text('创建自定义字段后，可在录入物资时添加个性化信息（如存放位置、品牌等）')
              .fontSize(13)
              .fontColor(CLR_TEXT_TIP)
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })

            Button('+ 新建自定义字段')
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor(CLR_BRAND)
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
        } else {
          List({ space: 10 }) {
            ForEach(this.customFields, (f: CustomField, index: number) => {
              ListItem() {
                this.fieldCard(f, index)
              }
            }, (f: CustomField) => `${f.id}_${f.order}_${f.name}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 30 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CLR_BG)
    .bindSheet($$this.showEditSheet, this.fieldEditSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: CLR_CARD,
      onDisappear: () => {
        this.showEditSheet = false;
      }
    })
  }

  @Builder
  fieldCard(f: CustomField, index: number) {
    Column({ space: 10 }) {
      Row() {
        Row({ space: 8 }) {
          Text(f.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(CLR_TEXT)

          Text(getFieldTypeName(f.type))
            .fontSize(12)
            .fontColor(CLR_BRAND)
            .backgroundColor(CLR_PREVIEW_BG)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
        }
        .layoutWeight(1)

        Row({ space: 4 }) {
          // 上移
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Text('↑')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(index > 0 ? CLR_TEXT : CLR_BORDER)
          }
          .backgroundColor(CLR_INPUT_BG)
          .borderRadius(8)
          .width(32)
          .height(32)
          .enabled(index > 0)
          .onClick(() => {
            this.moveFieldUp(index);
          })

          // 下移
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Text('↓')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(index < this.customFields.length - 1 ? CLR_TEXT : CLR_BORDER)
          }
          .backgroundColor(CLR_INPUT_BG)
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
            .fontColor(CLR_BRAND)
            .backgroundColor(CLR_PREVIEW_BG)
            .borderRadius(8)
            .height(32)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.openEditSheet(f);
            })

          // 删除
          Button('删除')
            .fontSize(13)
            .fontColor(CLR_DANGER)
            .backgroundColor('rgba(250, 42, 45, 0.08)')
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
            .fontSize(13)
            .fontColor(CLR_TEXT_SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(CLR_CARD)
  }

  @Builder
  fieldEditSheet() {
    Column({ space: 14 }) {
      Text(this.isEditing ? '编辑自定义字段' : '新建自定义字段')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(CLR_TEXT)
        .width('100%')
        .padding({ top: 6, bottom: 2 })

      if (this.sheetErrorMsg !== '') {
        Text(this.sheetErrorMsg)
          .fontSize(13)
          .fontColor(CLR_DANGER)
          .width('100%')
      }

      Column({ space: 6 }) {
        Text('字段名称 *')
          .fontSize(13)
          .fontColor(CLR_TEXT_SUB)
        TextInput({ text: this.inputName, placeholder: '如：存放位置、品牌、规格' })
          .fontSize(16)
          .backgroundColor(CLR_INPUT_BG)
          .borderRadius(12)
          .onChange((v: string) => {
            this.inputName = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text(this.isEditing ? '字段类型（创建后不可修改）' : '字段类型 *')
          .fontSize(13)
          .fontColor(CLR_TEXT_SUB)

        if (this.isEditing) {
          Row() {
            Text(getFieldTypeName(this.selectedType))
              .fontSize(15)
              .fontColor(CLR_TEXT)
              .fontWeight(FontWeight.Medium)
            Blank()
            Text('不可修改')
              .fontSize(13)
              .fontColor(CLR_TEXT_TIP)
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor(CLR_INPUT_BG)
        } else {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(CUSTOM_FIELD_TYPES, (type: CustomFieldType) => {
              Text(getFieldTypeName(type))
                .fontSize(14)
                .fontColor(this.selectedType === type ? Color.White : CLR_TEXT)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .borderRadius(20)
                .backgroundColor(this.selectedType === type ? CLR_BRAND : CLR_INPUT_BG)
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
        Column({ space: 8 }) {
          Text('单选选项（至少 2 个选项）*')
            .fontSize(13)
            .fontColor(CLR_TEXT_SUB)

          Row({ space: 8 }) {
            TextInput({ text: this.newOptionInput, placeholder: '输入选项名称，如：冷藏' })
              .fontSize(15)
              .backgroundColor(CLR_INPUT_BG)
              .borderRadius(12)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.newOptionInput = v;
              })

            Button('添加')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(CLR_BRAND)
              .borderRadius(12)
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
                Row({ space: 4 }) {
                  Text(opt)
                    .fontSize(13)
                    .fontColor(CLR_TEXT)
                  Text('✕')
                    .fontSize(12)
                    .fontColor(CLR_TEXT_SUB)
                    .padding({ left: 2, right: 2 })
                    .onClick(() => {
                      this.removeEnumOption(idx);
                    })
                }
                .padding({ left: 12, right: 8, top: 6, bottom: 6 })
                .borderRadius(16)
                .backgroundColor(CLR_INPUT_BG)
                .margin({ right: 8, bottom: 8 })
              }, (opt: string) => opt)
            }
            .width('100%')
            .padding({ top: 4 })
          } else {
            Text('暂无选项，请在上方的输入框中添加')
              .fontSize(12)
              .fontColor(CLR_TEXT_TIP)
              .margin({ top: 2 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor(CLR_INPUT_BG)
          .fontColor(CLR_TEXT)
          .fontSize(15)
          .onClick(() => {
            this.showEditSheet = false;
          })

        Button(this.isEditing ? '保存' : '创建')
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor(CLR_BRAND)
          .fontColor(Color.White)
          .fontSize(15)
          .onClick(() => {
            this.saveField();
          })
      }
      .width('100%')
      .margin({ top: 12, bottom: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
