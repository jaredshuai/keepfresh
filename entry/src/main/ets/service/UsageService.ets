/**
 * 使用日志服务（dogfood 可观测性，自用版）。
 *
 * 设计约定：
 * - 端侧 JSONL 追加写（一行一个事件），不上云；
 * - 写失败静默（日志永远不能影响产品功能）；
 * - 两周后通过 hdc 从应用沙箱直拉：见 docs/dogfood.md 检索命令。
 *
 * 实现注记：ArkTS 禁止无类型对象字面量，事件字段走显式参数 + 手工 JSON 拼接。
 */
import { fileIo, picker } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';


const LOG_FILE = 'usage_log.jsonl';
/** 超过该行数时截断保留后半（自用两周远达不到，纯防御） */
const MAX_LINES = 5000;

function jsonEscape(s: string): string {
  // 注意：不用正则字面量（wire-guard 的 stripSource 不识别正则，会误判后续代码）
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === '\\') {
      out += '\\\\';
    } else if (ch === '"') {
      out += '\\"';
    } else if (ch === '\n') {
      out += '\\n';
    } else if (ch === '\r') {
      out += '\\r';
    } else if (ch === '\t') {
      out += '\\t';
    } else {
      out += ch;
    }
  }
  return out;
}

export class UsageService {
  private static instance?: UsageService;
  private logPath: string = '';

  private constructor() {
  }

  public static getInstance(): UsageService {
    if (!UsageService.instance) {
      UsageService.instance = new UsageService();
    }
    return UsageService.instance;
  }

  /** 幂等初始化：任意入口拿到 Context 后调用一次即可 */
  public init(context: Context): void {
    if (this.logPath === '') {
      this.logPath = `${context.filesDir}/${LOG_FILE}`;
    }
  }

  /** 读取全量日志（轮转与导出用） */
  public readAll(): string {
    try {
      if (this.logPath === '' || !fileIo.accessSync(this.logPath)) {
        return '';
      }
      const file = fileIo.openSync(this.logPath, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        return String.fromCharCode(...new Uint8Array(buf));
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (e) {
      return '';
    }
  }

  /** 追加一条事件；kv 数量不限，值为 string/number/boolean */
  public logEvent(event: string, keys: string[], values: Array<string | number | boolean>): void {
    try {
      if (this.logPath === '' || keys.length !== values.length) {
        return;
      }
      let json = `{"ts":"${jsonEscape(new Date().toISOString())}","event":"${jsonEscape(event)}"`;
      for (let i = 0; i < keys.length; i++) {
        const v: string | number | boolean = values[i];
        if (typeof v === 'string') {
          json += `,"${jsonEscape(keys[i])}":"${jsonEscape(v)}"`;
        } else {
          json += `,"${jsonEscape(keys[i])}":${v}`;
        }
      }
      json += '}\n';
      this.appendAndRotate(json);
    } catch (e) {
      // 日志失败静默：不影响任何产品路径（调试期打 hilog）
      hilog.error(0x0000, 'UsageService', 'logEvent failed: %{public}s', (e as Error).message ?? '');
    }
  }

  private appendAndRotate(text: string): void {
    const file = fileIo.openSync(this.logPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file.fd);
    }
    this.rotateIfNeeded();
  }

  private rotateIfNeeded(): void {
    try {
      if (!fileIo.accessSync(this.logPath)) {
        return;
      }
      const stat = fileIo.statSync(this.logPath);
      if (stat.size < 512 * 1024) {
        return; // 512KB 以下不折腾
      }
      const all = this.readAll();
      const lines = all.split('\n').filter((l: string): boolean => l.length > 0);
      if (lines.length <= MAX_LINES) {
        return;
      }
      const keep = lines.slice(lines.length - MAX_LINES).join('\n') + '\n';
      fileIo.unlinkSync(this.logPath);
      const file = fileIo.openSync(this.logPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, keep);
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (e) {
      // 静默
    }
  }

  /* ── 语义化事件（dogfood 观测协议见 docs/dogfood.md）── */

  public logAppOpen(): void {
    this.logEvent('app_open', [], []);
  }

  /** 入库完成：via = barcode | suggestion | manual */
  public logItemAdded(name: string, via: string, isEdit: boolean, durationMs: number,
    shelfLifeDays: number, monthsMode: boolean): void {
    this.logEvent('item_added',
      ['name', 'via', 'is_edit', 'duration_ms', 'shelf_life_days', 'months_mode'],
      [name, via, isEdit, durationMs, shelfLifeDays, monthsMode]);
  }

  public logSuggestionShown(name: string): void {
    this.logEvent('suggestion_shown', ['name'], [name]);
  }

  public logSuggestionApplied(name: string): void {
    this.logEvent('suggestion_applied', ['name'], [name]);
  }

  public logNotificationClicked(level: string): void {
    this.logEvent('notification_clicked', ['level'], [level]);
  }

  public logStatusChanged(name: string, status: string): void {
    this.logEvent('status_changed', ['name', 'status'], [name, status]);
  }

  public logItemDeleted(name: string): void {
    this.logEvent('item_deleted', ['name'], [name]);
  }

  public logReminderPublished(expiredCount: number, nearCount: number): void {
    this.logEvent('reminder_published', ['expired', 'near'], [expiredCount, nearCount]);
  }

  /** 手工导出：日志另存为用户所选位置的 jsonl 文件（真机无 hdc 场景的备用通道） */
  public async exportUsageLog(context: Context, uiContext: UIContext): Promise<void> {
    const showToast = (message: string): void => {
      try {
        uiContext.getPromptAction().showToast({ message });
      } catch (e) {
        hilog.error(0x0000, 'UsageService', 'toast failed: %s', (e as BusinessError).message);
      }
    };
    try {
      this.init(context);
      const content = this.readAll();
      if (content === '') {
        showToast('暂无使用日志');
        return;
      }
      const documentPicker = new picker.DocumentViewPicker(context);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`keepfresh_usage_${new Date().toISOString().slice(0, 10).replace(/-/g, '')}.jsonl`];
      const uris: Array<string> = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        return; // 用户取消
      }
      let fd: number = -1;
      try {
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
        fd = file.fd;
        fileIo.writeSync(fd, content);
        showToast('使用日志已导出');
      } finally {
        if (fd >= 0) {
          fileIo.closeSync(fd);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, 'UsageService', 'export failed: %s', err.message);
      showToast('导出失败，请重试');
    }
  }
}
