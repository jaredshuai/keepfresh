# ADR 0001: 采用后台代理提醒（reminderAgentManager）实现每日离线临期汇总通知

- **状态**：已接受 (Accepted)
- **日期**：2026-08-19
- **决策人**：产品/架构

---

## 1. 背景与问题描述
保质期管理应用的核心价值在于“在物品变质之前提醒用户”。
先前版本的 `NotificationService` 仅能在应用处于前台运行或打开时发布即时本地通知。一旦用户杀掉进程或锁屏，应用将无法在指定时刻向用户发出提醒，导致过期无法及时处理。

## 2. 决策考量与候选方案

### 候选方案 A：长时任务 / BackgroundTasksKit WorkScheduler
- **优点**：后台允许执行一段自定义代码逻辑。
- **缺点**：受系统电源管理与低功耗策略约束（尤其是后台进程保活受限），无法保证在每天特定时刻（如 09:00:00）精准唤醒执行并弹窗。

### 候选方案 B：系统级代理提醒（reminderAgentManager，已选定）
- **优点**：
  1. **零后台常驻**：无需应用保持后台运行，由 HarmonyOS 系统底层服务代理托管定时触发。
  2. **精准可靠**：支持 `ReminderRequestCalendar` 按每日指定小时/分钟准时触发通知、响铃或振动。
  3. **丰富交互**：支持设置 `WantAgent`，用户点击系统通知时可直接携带参数拉起 `EntryAbility`，直达「⚠️ 临期」列表视图。
  4. **免打扰控制**：配合本地首选项（`preferences`）与物资数据库查询，在无临期/无过期时静默不打扰用户。
- **缺点**：需要申请系统代理提醒权限（`ohos.permission.PUBLISH_AGENT_REMINDER`）。

---

## 3. 架构设计与实施细则

1. **权限配置**：在 `module.json5` 中声明 `ohos.permission.PUBLISH_AGENT_REMINDER` 权限。
2. **调度策略**：
   - 默认提醒时间：每日 `09:00`。
   - 触发逻辑：当数据发生变动（添加/编辑/删除物资）或用户更改提醒设置时，自动重新计算并注册次日/每日的代理提醒 `ReminderRequestCalendar`。
3. **点击唤醒联动**：
   - 提醒的 `wantAgent` 设置目标 Ability 为 `EntryAbility`，携带参数 `{ filterLevel: 'NEAR' }`。
   - `EntryAbility.onWindowStageCreate` 与 `onNewWant` 读取参数并传递给首页，首页自动激活「临期」筛选 Tab。
4. **用户设置持久化**：
   - 使用 `@kit.ArkData` 的 `preferences` 保存 `reminder_enabled: boolean` 与 `reminder_time: string` (如 `"09:00"`)。

---

## 4. 影响与收益
- 解决应用进程关闭后无法提醒的关键短板。
- 极大提升保质期管理的实用性与产品留存率。
