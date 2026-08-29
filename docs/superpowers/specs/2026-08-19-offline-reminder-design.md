# KeepFresh 后台离线定时临期提醒技术规格设计方案

- **日期**：2026-08-19
- **状态**：已批准 (Approved)
- **对应 ADR**：[ADR 0001](file:///E:/codespace/keepfresh/docs/adr/0004-daily-summary-offline-reminder.md)

---

## 1. 概述与需求目标

### 1.1 背景
先前版本的通知功能仅在应用打开时发布即时本地通知。一旦应用进入后台或被系统杀死，用户无法收到任何到期警告。

### 1.2 目标与业务规则
1. **系统代理提醒（`reminderAgentManager`）**：
   - 使用 `@kit.BackgroundTasksKit` 的 `reminderAgentManager` 发布日历型提醒（`ReminderRequestCalendar`）。
   - 每日在设定时间（默认 `09:00`）自动触发系统通知，无需应用常驻后台。
2. **静默与免打扰逻辑**：
   - 只有在存在 `EXPIRED`（已过期）或 `NEAR`（3天内临期）物资时，才下发通知；若所有物资安全或无物资，系统完全静默。
3. **点击直达联动**：
   - 用户点击通知时，通过 `wantAgent` 唤醒 `EntryAbility`，携带 `{ filterLevel: 'NEAR' }`。
   - 首页 `Index.ets` 捕获该参数，自动将顶部状态筛选切换为「⚠️ 临期」标签，呈现紧急待处理物品。
4. **设置持久化（`Preferences`）**：
   - 支持用户在首页设置抽屉/面板中配置提醒时间（小时/分钟）以及一键开关，使用 `@kit.ArkData` 的 `preferences` 持久化。

---

## 2. 模块划分与接口设计

```
entry/src/main/
├── module.json5                          # 声明 ohos.permission.PUBLISH_AGENT_REMINDER 权限
├── ets/
│   ├── service/
│   │   └── ReminderService.ets          # 代理提醒生命周期、首选项管理与定时注册
│   ├── entryability/
│   │   └── EntryAbility.ets              # 处理通知 Want 点击唤醒与参数路由
│   └── pages/
│       └── Index.ets                     # 响应通知筛选跳转 + 提供提醒设置浮层/入口
```

### 2.1 `ReminderService.ets` 核心接口

```typescript
export interface ReminderSettings {
  enabled: boolean;
  hour: number;     // 0~23, 默认 9
  minute: number;   // 0~59, 默认 0
}

export class ReminderService {
  public static getInstance(): ReminderService;
  public async init(context: common.UIAbilityContext | Context): Promise<void>;
  public async getSettings(): Promise<ReminderSettings>;
  public async updateSettings(settings: ReminderSettings): Promise<void>;
  public async syncDailyReminder(context: common.UIAbilityContext | Context): Promise<void>;
  public async cancelAllReminders(): Promise<void>;
}
```

---

## 3. 详细执行流程

```
[物资变更 (Add/Edit/Delete) 或 设置更新]
                    ↓
   `ReminderService.syncDailyReminder()`
                    ↓
  1. 读取当前设置 `getSettings()` (若 enabled = false 则取消旧提醒并退出)
  2. 查询 `MaterialDb` 计算当前临期与过期物资数量 (nearCount, expiredCount)
  3. 若 (nearCount + expiredCount == 0) -> 取消旧提醒，保持静默
  4. 若 (nearCount + expiredCount > 0) ->
     - 构建 `wantAgent` (指向 EntryAbility, 参数 filterLevel = 'NEAR')
     - 构建 `ReminderRequestCalendar` (设定每日指定 hour:minute 触发，标题为“KeepFresh 临期提醒”)
     - 调用 `reminderAgentManager.publishReminder(reminder)`
```

---

## 4. 验证与测试方案
1. **首选项读写单测**：验证 `getSettings` / `updateSettings` 数据持久化一致性。
2. **提醒内容与触发条件测试**：
   - 验证 0 临期时静默逻辑；
   - 验证多件临期时文案拼装（“X 件已过期，Y 件即将到期”）。
3. **点击 Want 路由测试**：
   - 验证通过 `EntryAbility` 传递 `filterLevel` 时，首页响应并选中对应 Tab。
