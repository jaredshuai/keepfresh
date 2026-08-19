/**
 * 首页：临期概览 + 物资列表（按到期日升序）—— 鸿蒙官方设计风格。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, ExpiryLevel } from '../model/Material';
import { MaterialDb } from '../db/MaterialDb';
import { ExpiryStats, levelOf, levelColor, levelText, remainingDays, statsOf } from '../service/ExpiryService';
import { ensureNotificationEnabled, publishExpiryAlert, requestNotificationEnable } from '../service/NotificationService';

/* ───── 鸿蒙官方色值体系 ───── */
const CLR_BRAND = '#2FA84F';
const CLR_BG = '#F1F3F5';
const CLR_CARD = '#FFFFFF';
const CLR_TEXT = '#182431';
const CLR_TEXT_SUB = '#99182431';
const CLR_TEXT_TIP = '#4D182431';
const CLR_BORDER = '#E5E5E5';
const CLR_DANGER = '#FA2A2D';
const CLR_WARNING = '#FF8D00';
const CLR_SUCCESS = '#2FA84F';

enum ListFilter {
  ALL = 0,
  NEAR = 1,
  EXPIRED = 2
}

/** 每次启动只发一条汇总通知 */
let notifiedThisSession: boolean = false;

@Entry
@Component
struct Index {
  @State materials: Material[] = [];
  @State stats: ExpiryStats = { total: 0, expired: 0, near: 0, safe: 0 };
  @State filter: ListFilter = ListFilter.ALL;
  @State loading: boolean = true;
  private db: MaterialDb = MaterialDb.getInstance();

  onPageShow(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.db.init(ctx)
      .then(() => {
        return this.refresh();
      })
      .catch((e: BusinessError) => {
        console.error(`init db failed: ${e.message}`);
        this.loading = false;
      });
    this.setupNotification(ctx);
  }

  private async setupNotification(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const enabled: boolean = await ensureNotificationEnabled(ctx);
      if (!enabled) {
        await requestNotificationEnable(ctx);
      }
    } catch (e) {
      console.error(`setup notification failed: ${(e as BusinessError).message}`);
    }
  }

  async refresh(): Promise<void> {
    try {
      const list: Material[] = await this.db.listAll();
      this.materials = list;
      this.stats = statsOf(list);
      if (!notifiedThisSession && this.stats.near + this.stats.expired > 0) {
        notifiedThisSession = true;
        await publishExpiryAlert(this.stats.near, this.stats.expired);
      }
    } catch (e) {
      console.error(`load materials failed: ${(e as BusinessError).message}`);
    } finally {
      this.loading = false;
    }
  }

  visibleList(): Material[] {
    if (this.filter === ListFilter.NEAR) {
      return this.materials.filter((m: Material): boolean => levelOf(m) === ExpiryLevel.NEAR);
    }
    if (this.filter === ListFilter.EXPIRED) {
      return this.materials.filter((m: Material): boolean => levelOf(m) === ExpiryLevel.EXPIRED);
    }
    return this.materials;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          Column() {
            Text('KeepFresh')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(CLR_TEXT)
            Text('物资保质期管理')
              .fontSize(14)
              .fontColor(CLR_TEXT_SUB)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Row({ space: 8 }) {
          this.statCard('全部', this.stats.total, ListFilter.ALL, CLR_TEXT)
          this.statCard('临期', this.stats.near, ListFilter.NEAR, CLR_WARNING)
          this.statCard('已过期', this.stats.expired, ListFilter.EXPIRED, CLR_DANGER)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })

        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40).color(CLR_BRAND)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.visibleList().length === 0) {
          Column({ space: 8 }) {
            Text(this.stats.total === 0 ? '还没有物资' : '当前筛选下没有物资')
              .fontSize(16)
              .fontColor(CLR_TEXT_SUB)
            if (this.stats.total === 0) {
              Text('点击右下角 + 添加第一件物资')
                .fontSize(14)
                .fontColor(CLR_TEXT_TIP)
            }
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.visibleList(), (m: Material) => {
              ListItem() {
                this.materialCard(m)
              }
            }, (m: Material) => m.id.toString())
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 88 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      Button() {
        Text('+')
          .fontSize(28)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width(56)
      .height(56)
      .borderRadius(16)
      .backgroundColor(CLR_BRAND)
      .shadow({ radius: 12, color: 'rgba(47,168,79,0.25)', offsetX: 0, offsetY: 4 })
      .margin(16)
      .onClick(() => {
        router.pushUrl({ url: 'pages/AddItem' });
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CLR_BG)
  }

  @Builder
  statCard(label: string, count: number, f: ListFilter, color: string) {
    Column() {
      Text(count.toString())
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(12)
        .fontColor(CLR_TEXT_SUB)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .borderRadius(16)
    .backgroundColor(CLR_CARD)
    .border(this.filter === f
      ? { width: 2, color: CLR_BRAND }
      : { width: 1, color: CLR_BORDER })
    .onClick(() => {
      this.filter = f;
    })
  }

  @Builder
  materialCard(m: Material) {
    Row() {
      Column() {
        Text(m.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(CLR_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${m.category} · ${m.quantity}${m.unit}`)
          .fontSize(13)
          .fontColor(CLR_TEXT_SUB)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text(levelText(levelOf(m), remainingDays(m)))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
        Text(m.expiryDate)
          .fontSize(11)
          .fontColor('rgba(255,255,255,0.9)')
          .margin({ top: 2 })
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(10)
      .backgroundColor(levelColor(levelOf(m)))
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(CLR_CARD)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ItemDetail', params: { id: m.id } });
    })
  }
}
