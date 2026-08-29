/**
 * 分类 / 位置管理页 —— 包豪斯（Bauhaus）风格。
 * 完整 CRUD：新增 / 重命名（同步物资引用）/ 删除（使用中拦截）/ 上移下移排序。
 * 预设项只读，自定义项可编辑。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DEFAULT_CATEGORIES, DEFAULT_LOCATIONS, DEFAULT_UNITS } from '../model/Material';
import { MaterialDb, NameDef, NameKind } from '../db/MaterialDb';
import { Theme } from '../common/Theme';
import { HardShadowBox, HardShadowCard } from '../common/HardShadow';

@Entry
@Component
struct CategoryManager {
  @StorageProp('avoidTopVp') avoidTopVp: number = 0;
  @StorageProp('avoidBottomVp') avoidBottomVp: number = 0;
  @State activeKind: string = 'category';   // 'category' | 'location' | 'unit'
  @State defs: NameDef[] = [];              // 自定义定义（可编辑）
  @State effectiveNames: string[] = [];     // 有效名称（含预设与已使用）
  @State loading: boolean = true;
  @State showEditSheet: boolean = false;
  @State editingId: number = -1;            // -1 = 新建
  @State inputName: string = '';
  @State usageCounts: Record<string, number> = {};
  private db: MaterialDb = MaterialDb.getInstance();

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

  private kind(): NameKind {
    if (this.activeKind === 'category' || this.activeKind === 'location' || this.activeKind === 'unit') {
      return this.activeKind;
    }
    return 'category';
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (e) {
      console.error(`show toast failed: ${(e as BusinessError).message}`);
    }
  }

  private defaults(): string[] {
    if (this.activeKind === 'location') {
      return DEFAULT_LOCATIONS;
    }
    if (this.activeKind === 'unit') {
      return DEFAULT_UNITS;
    }
    return DEFAULT_CATEGORIES;
  }

  private kindLabel(): string {
    if (this.activeKind === 'location') {
      return '位置';
    }
    if (this.activeKind === 'unit') {
      return '单位';
    }
    return '分类';
  }

  private async load(): Promise<void> {
    try {
      const k: NameKind = this.kind();
      const defs: NameDef[] = await this.db.listNameDefs(k);
      this.defs = defs;
      const effective: string[] = await this.db.listEffectiveNames(k, this.defaults());
      this.effectiveNames = effective;
      // 使用量统计（全部有效名称）
      const counts: Record<string, number> = {};
      for (let i = 0; i < effective.length; i++) {
        const n: string = effective[i];
        counts[n] = await this.db.countNameUsage(k, n);
      }
      this.usageCounts = counts;
    } catch (e) {
      console.error(`load names failed: ${(e as BusinessError).message}`);
    } finally {
      this.loading = false;
    }
  }

  private switchKind(k: string): void {
    if (this.activeKind === k) {
      return;
    }
    this.activeKind = k;
    this.loading = true;
    this.load();
  }

  private openCreateSheet(): void {
    this.editingId = -1;
    this.inputName = '';
    this.showEditSheet = true;
  }

  private openRenameSheet(def: NameDef): void {
    this.editingId = def.id;
    this.inputName = def.name;
    this.showEditSheet = true;
  }

  private async saveName(): Promise<void> {
    const trimmed: string = this.inputName.trim();
    if (trimmed.length === 0) {
      this.toast(`请输入${this.kindLabel()}名称`);
      return;
    }
    if (trimmed.length > 20) {
      this.toast('名称不能超过 20 字');
      return;
    }
    try {
      if (this.editingId < 0) {
        const rowId: number = await this.db.insertNameDef(this.kind(), trimmed);
        if (rowId < 0) {
          this.toast('名称已存在');
          return;
        }
        this.toast('已添加');
      } else {
        const affected: number = await this.db.renameNameDef(this.editingId, trimmed);
        if (affected < 0) {
          this.toast('名称已存在或无效');
          return;
        }
        this.toast('已重命名（物资引用已同步）');
      }
      this.showEditSheet = false;
      this.load();
    } catch (e) {
      console.error(`save name failed: ${(e as BusinessError).message}`);
      this.toast('保存失败，请重试');
    }
  }

  private confirmDelete(def: NameDef): void {
    const count: number = this.usageCounts[def.name] ?? 0;
    const message: string = count > 0
      ? `「${def.name}」正被 ${count} 件物资使用，删除定义不影响这些物资，但名称将不再出现在管理列表。确定删除？`
      : `确定删除「${def.name}」吗？`;
    this.getUIContext().showAlertDialog({
      title: `删除${this.kindLabel()}`,
      message: message,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.danger,
        action: () => {
          this.doDelete(def);
        }
      }
    });
  }

  private async doDelete(def: NameDef): Promise<void> {
    try {
      await this.db.removeNameDef(def.id);
      this.toast('已删除');
      this.load();
    } catch (e) {
      console.error(`delete name failed: ${(e as BusinessError).message}`);
    }
  }

  private async move(def: NameDef, delta: number): Promise<void> {
    const idx: number = this.defs.indexOf(def);
    const target: number = idx + delta;
    if (idx < 0 || target < 0 || target >= this.defs.length) {
      return;
    }
    try {
      this.defs = await this.db.moveNameDef(this.kind(), idx, target);
      this.load();
    } catch (e) {
      console.error(`move name failed: ${(e as BusinessError).message}`);
    }
  }

  /** 名称是否预设（只读） */
  private isPreset(name: string): boolean {
    return this.defaults().indexOf(name) >= 0;
  }

  /** 名称是否有自定义定义（可编辑） */
  private findDef(name: string): NameDef | undefined {
    for (let i = 0; i < this.defs.length; i++) {
      if (this.defs[i].name === name) {
        return this.defs[i];
      }
    }
    return undefined;
  }

  build() {
    Column() {
      // 顶部导航：返回 + 标题 + 新建按钮
      Row() {
        this.backButton()

        Text(`管理${this.kindLabel()}`)
          .fontSize(Theme.textTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .margin({ left: Theme.elementGap })
          .layoutWeight(1)

        this.primarySmallBtn('新建', () => {
          this.openCreateSheet();
        })
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding,
        right: Theme.pagePadding,
        top: 16,
        bottom: 12
      })

      // 分类 / 位置 / 单位切换 Chip
      Row({ space: Theme.smallGap }) {
        this.kindSwitchChip('category', '分类')
        this.kindSwitchChip('location', '位置')
        this.kindSwitchChip('unit', '单位')
      }
      .width('100%')
      .padding({
        left: Theme.pagePadding,
        right: Theme.pagePadding,
        bottom: Theme.smallGap
      })
      .justifyContent(FlexAlign.Start)

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(Theme.ink)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.effectiveNames.length === 0) {
        Column({ space: Theme.smallGap }) {
          Text(`还没有${this.kindLabel()}`)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary)
          Text('点击右上角新建添加')
            .fontSize(Theme.textCaption)
            .fontColor(Theme.textTertiary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: Theme.smallGap }) {
            ForEach(this.effectiveNames, (name: string, idx: number) => {
              this.nameRow(name, idx)
            }, (name: string) => name)
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
    .bindSheet($$this.showEditSheet, this.editSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: Theme.sheetBg,
      onDisappear: () => {
        this.showEditSheet = false;
      }
    })
  }

  @Builder
  backButton() {
    HardShadowBox({boxWidth: Theme.iconBtnSize, boxHeight: Theme.iconBtnSize, topStart: true}) {

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

  /** 顶部新建小按钮：深黄底白字 */
  @Builder
  primarySmallBtn(label: string, onClick: () => void) {
    Stack() {
      Column()
        .height(36)
        .backgroundColor(Theme.ink)
        .margin({ left: 3, top: 3 })
      Text(label)
        .fontSize(Theme.textSmall)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.textWhite)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(Theme.yellowDark)
        .border(Theme.borderThin)
        .onClick(onClick)
    }
    .padding({ right: 3, bottom: 3 })
  }

  /** 分类/位置切换 Chip */
  @Builder
  kindSwitchChip(kind: string, label: string) {
    Stack() {
      Column()
        .height(32)
        .backgroundColor(Theme.ink)
        .margin({ left: 3, top: 3 })
      Text(label)
        .fontSize(Theme.textSmall)
        .fontWeight(this.activeKind === kind ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.activeKind === kind ? Theme.textWhite : Theme.textPrimary)
        .padding({ left: 16, right: 16, top: 7, bottom: 7 })
        .backgroundColor(this.activeKind === kind ? Theme.yellowDark : Theme.cardBg)
        .border(Theme.borderThin)
        .onClick(() => {
          this.switchKind(kind);
        })
    }
    .padding({ right: 3, bottom: 3 })
  }

  /** 名称行卡片：预设只读 / 自定义可编辑（上下移+重命名+删除） */
  @Builder
  nameRow(name: string, idx: number) {
    HardShadowCard({shadowMode: 0, topStart: true}) {

      Row() {
        Column({ space: Theme.tinyGap }) {
          Text(name)
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary)
          Text(this.isPreset(name) ? '预设（不可编辑）' : `${this.usageCounts[name] ?? 0} 件物资使用中`)
            .fontSize(Theme.textCaption)
            .fontColor(this.isPreset(name) ? Theme.textTertiary : Theme.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.isPreset(name) && this.findDef(name) !== undefined) {
          Row({ space: Theme.tinyGap }) {
            // 上移/下移（沿用 CustomFieldManager 的紧凑按钮模式）
            this.smallIconBtn(
              $r('sys.symbol.chevron_up'),
              name,
              -1,
              () => {
                const def: NameDef | undefined = this.findDef(name);
                if (def !== undefined) {
                  this.move(def, -1);
                }
              }
            )
            this.smallIconBtn(
              $r('sys.symbol.chevron_down'),
              name,
              1,
              () => {
                const def: NameDef | undefined = this.findDef(name);
                if (def !== undefined) {
                  this.move(def, 1);
                }
              }
            )
            this.smallTextBtn('重命名', () => {
              const def: NameDef | undefined = this.findDef(name);
              if (def !== undefined) {
                this.openRenameSheet(def);
              }
            })
            this.smallDangerBtn('删除', () => {
              const def: NameDef | undefined = this.findDef(name);
              if (def !== undefined) {
                this.confirmDelete(def);
              }
            })
          }
        }
      }
      .width('100%')
      .padding(Theme.cardPadding)
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
    }
  }

  /** 上移是否可用（该名称的自定义定义不在首位） */
  private moveUpEnabled(name: string): boolean {
    const def: NameDef | undefined = this.findDef(name);
    if (def === undefined) {
      return false;
    }
    return this.defs.indexOf(def) > 0;
  }

  /** 下移是否可用（该名称的自定义定义不在末位） */
  private moveDownEnabled(name: string): boolean {
    const def: NameDef | undefined = this.findDef(name);
    if (def === undefined) {
      return false;
    }
    return this.defs.indexOf(def) < this.defs.length - 1;
  }

  /** 上移/下移 32x32 白底黑边 */
  @Builder
  smallIconBtn(symbol: Resource, name: string, dir: number, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(symbol)
        .fontSize(16)
        // enabled 在 builder 体内实时求值：按值传参不随移动/增删刷新
        .fontColor([this.moveEnabled(name, dir) ? Theme.textPrimary : Theme.textTertiary])
    }
    .backgroundColor(Theme.cardBg)
    .width(32)
    .height(32)
    .borderRadius(Theme.iconBtnRadius)
    .border(Theme.borderThin)
    .opacity(this.moveEnabled(name, dir) ? 1 : 0.3)
    .enabled(this.moveEnabled(name, dir))
    .onClick(onClick)
  }

  /** 上移/下移按钮在当前位置是否可用（dir: -1 上移 / 1 下移） */
  private moveEnabled(name: string, dir: number): boolean {
    return dir < 0 ? this.moveUpEnabled(name) : this.moveDownEnabled(name);
  }

  /** 重命名小按钮：深黄底白字 */
  @Builder
  smallTextBtn(label: string, onClick: () => void) {
    Text(label)
      .fontSize(Theme.textSmall)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textWhite)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(Theme.yellowDark)
      .border(Theme.borderThin)
      .onClick(onClick)
  }

  /** 删除小按钮：白底红字 */
  @Builder
  smallDangerBtn(label: string, onClick: () => void) {
    Text(label)
      .fontSize(Theme.textSmall)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.danger)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(Theme.cardBg)
      .border(Theme.borderThin)
      .onClick(onClick)
  }

  /** 新建/重命名底部 Sheet */
  @Builder
  editSheet() {
    Column({ space: Theme.elementGap }) {
      Row() {
        Text(this.editingId < 0 ? `新建${this.kindLabel()}` : `重命名${this.kindLabel()}`)
          .fontSize(Theme.textHeadline)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })

      HardShadowCard({shadowMode: 48}) {
        TextInput({ text: this.inputName, placeholder: `输入${this.kindLabel()}名称（最多 20 字）` })
          .fontSize(Theme.textBody)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textTertiary)
          .backgroundColor(Theme.inputBg)
          .border(Theme.borderThin)
          .borderRadius(Theme.inputRadius)
          .height(48)
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.inputName = v;
          })
      }

      if (this.editingId >= 0) {
        Text('重命名会同步更新所有引用此名称的物资')
          .fontSize(Theme.textCaption)
          .fontColor(Theme.textSecondary)
          .width('100%')
      }

      Row({ space: Theme.elementGap }) {
        Stack() {
          Column()
            .width('100%')
            .height(44)
            .backgroundColor(Theme.ink)
            .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
          Text('取消')
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary)
            .width('100%')
            .height(44)
            .textAlign(TextAlign.Center)
            .backgroundColor(Theme.cardBg)
            .border(Theme.borderThin)
            .onClick(() => {
              this.showEditSheet = false;
            })
        }
        .layoutWeight(1)
        .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })

        Stack() {
          Column()
            .width('100%')
            .height(44)
            .backgroundColor(Theme.ink)
            .margin({ left: Theme.hardShadowOffset, top: Theme.hardShadowOffset })
          Text('保存')
            .fontSize(Theme.textBody)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textWhite)
            .width('100%')
            .height(44)
            .textAlign(TextAlign.Center)
            .backgroundColor(Theme.yellowDark)
            .border(Theme.borderThin)
            .onClick(() => {
              this.saveName();
            })
        }
        .layoutWeight(1)
        .padding({ right: Theme.hardShadowOffset, bottom: Theme.hardShadowOffset })
      }
      .width('100%')
      .margin({ top: 8 })

      Column().width('100%').height(8)
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
