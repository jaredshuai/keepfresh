# KeepFresh 后台离线定时临期提醒实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于 HarmonyOS 系统级后台代理提醒（`reminderAgentManager`）与首选项（`preferences`），实现应用退出后的每日定时临期汇总通知，支持零临期静默免打扰、用户自定义提醒时间及通知点击直达「临期」筛选列表。

**Architecture:**
- `module.json5`: 声明 `ohos.permission.PUBLISH_AGENT_REMINDER` 权限。
- `ReminderService.ets`: 管理用户提醒设置（开关、触发时间），查询当前数据库临期物资统计，按需注册/更新 `ReminderRequestCalendar` 系统代理提醒。
- `EntryAbility.ets`: 接收通知点击 `Want` 参数并转发给应用主窗口。
- `Index.ets`: 支持接收外部参数切换至「⚠️ 临期」Tab，并在顶部右上角提供提醒设置抽屉/弹窗。

**Tech Stack:** ArkTS, ArkUI, @kit.BackgroundTasksKit (`reminderAgentManager`), @kit.AbilityKit (`wantAgent`, `UIAbility`), @kit.ArkData (`preferences`, `relationalStore`).

---

### Task 1: 权限声明与首选项配置层 (`module.json5`, `ReminderService.ets`)

**Files:**
- Modify: `entry/src/main/module.json5`
- Create: `entry/src/main/ets/service/ReminderService.ets`

**Interfaces:**
- Produces: 
  - `interface ReminderSettings { enabled: boolean; hour: number; minute: number; }`
  - `ReminderService.getSettings(): Promise<ReminderSettings>`
  - `ReminderService.updateSettings(settings: ReminderSettings): Promise<void>`

- [ ] **Step 1: 在 `module.json5` 中声明 `ohos.permission.PUBLISH_AGENT_REMINDER`**

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.PUBLISH_AGENT_REMINDER"
  }
]
```

- [ ] **Step 2: 创建 `ReminderService.ets` 并实现 `preferences` 首选项读写**

```typescript
import { preferences } from '@kit.ArkData';
import { common, Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ReminderService';
const PREF_NAME = 'keepfresh_reminder_prefs';
const KEY_ENABLED = 'reminder_enabled';
const KEY_HOUR = 'reminder_hour';
const KEY_MINUTE = 'reminder_minute';

export interface ReminderSettings {
  enabled: boolean;
  hour: number;
  minute: number;
}

export class ReminderService {
  private static instance: ReminderService;
  private prefStore: preferences.Preferences | undefined = undefined;

  private constructor() {}

  public static getInstance(): ReminderService {
    if (!ReminderService.instance) {
      ReminderService.instance = new ReminderService();
    }
    return ReminderService.instance;
  }

  public async init(context: Context): Promise<void> {
    if (this.prefStore) {
      return;
    }
    try {
      this.prefStore = await preferences.getPreferences(context, PREF_NAME);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to get preferences: %{public}s', e.message);
    }
  }

  public async getSettings(): Promise<ReminderSettings> {
    if (!this.prefStore) {
      return { enabled: true, hour: 9, minute: 0 };
    }
    const enabled = await this.prefStore.get(KEY_ENABLED, true) as boolean;
    const hour = await this.prefStore.get(KEY_HOUR, 9) as number;
    const minute = await this.prefStore.get(KEY_MINUTE, 0) as number;
    return { enabled, hour, minute };
  }

  public async updateSettings(settings: ReminderSettings): Promise<void> {
    if (!this.prefStore) {
      return;
    }
    await this.prefStore.put(KEY_ENABLED, settings.enabled);
    await this.prefStore.put(KEY_HOUR, settings.hour);
    await this.prefStore.put(KEY_MINUTE, settings.minute);
    await this.prefStore.flush();
  }
}
```

- [ ] **Step 3: 提交 Task 1**

```bash
git add entry/src/main/module.json5 entry/src/main/ets/service/ReminderService.ets
git commit -m "feat(reminder): add reminder permission and preferences configuration"
```

---

### Task 2: 封装 `reminderAgentManager` 代理提醒注册与 WantAgent (`ReminderService.ets`)

**Files:**
- Modify: `entry/src/main/ets/service/ReminderService.ets`

**Interfaces:**
- Consumes: `@kit.BackgroundTasksKit`, `@kit.AbilityKit`, `MaterialDb`, `ExpiryService`
- Produces: 
  - `ReminderService.syncDailyReminder(context: Context): Promise<void>`
  - `ReminderService.cancelAllReminders(): Promise<void>`

- [ ] **Step 1: 在 `ReminderService.ets` 中实现 `syncDailyReminder` 与 `cancelAllReminders`**

```typescript
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { MaterialDb } from '../db/MaterialDb';
import { levelOf } from './ExpiryService';
import { Material } from '../model/Material';

// 核心实现：
// 1. 读取设置，若 disabled 则 cancelAllReminders 并返回。
// 2. 查询 MaterialDb 获取全部物品，计算 expiredCount 与 nearCount。
// 3. 若 expiredCount + nearCount === 0，则 cancelAllReminders（静默）并返回。
// 4. 若 > 0，则先 cancelAllReminders，然后构建 WantAgentInfo (指向 EntryAbility, parameters: { filterLevel: 'NEAR' })
// 5. 构建 reminderAgentManager.ReminderRequestCalendar，设置 repeatMonths/repeatDays/hour/minute 及文案
// 6. 调用 reminderAgentManager.publishReminder(calendarReq) 发布代理提醒。
```

- [ ] **Step 2: 提交 Task 2**

```bash
git add entry/src/main/ets/service/ReminderService.ets
git commit -m "feat(reminder): implement reminderAgentManager scheduling and wantAgent binding"
```

---

### Task 3: 物资生命周期与启动时自动同步 (`AddItem.ets`, `ItemDetail.ets`, `EntryAbility.ets`)

**Files:**
- Modify: `entry/src/main/ets/pages/AddItem.ets`
- Modify: `entry/src/main/ets/pages/ItemDetail.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`

- [ ] **Step 1: 在 `AddItem.ets` 保存后触发 `ReminderService.syncDailyReminder`**
- [ ] **Step 2: 在 `ItemDetail.ets` 删除后触发 `ReminderService.syncDailyReminder`**
- [ ] **Step 3: 在 `EntryAbility.ets` `onWindowStageCreate` 中初始化并传递 `want.parameters`**

- [ ] **Step 4: 提交 Task 3**

```bash
git add entry/src/main/ets/pages/AddItem.ets entry/src/main/ets/pages/ItemDetail.ets entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat(reminder): sync offline reminders on data mutations and app startup"
```

---

### Task 4: 首页 `Index.ets` 交互联动与提醒设置面板

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: 响应通知点击参数 `filterLevel === 'NEAR'` 自动切换选中 Tab 为临期**
- [ ] **Step 2: 在顶部标题栏右侧增加「🔔 提醒设置」按钮，点击弹出设置浮层**
- [ ] **Step 3: 设置浮层提供：开启/关闭开关、时间选择器（TimePicker）、保存并实时触发 `syncDailyReminder`**
- [ ] **Step 4: 提交 Task 4**

```bash
git add entry/src/main/ets/pages/Index.ets
git commit -m "feat(ui): add reminder settings panel and handle notification deep-link filter"
```
