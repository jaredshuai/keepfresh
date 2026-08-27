/**
 * 输入校验纯函数（零依赖，Node 可测 —— ticket #16）。
 *
 * 约定：凡需要被 test/ 直接覆盖的校验逻辑一律放本模块；
 * service 层的同名方法只做转发，保证测试对象是生产实现而非副本。
 */

/** 临期天数阈值合法范围（validateNearExpiryDays 与 setNearExpiryThreshold 共用） */
export const NEAR_EXPIRY_DAYS_MIN: number = 1;
export const NEAR_EXPIRY_DAYS_MAX: number = 365;

/**
 * 校验临期天数输入
 * @returns 错误信息文案（UI 直接展示，改动需同步检查用例），通过返回 null
 */
export function validateNearExpiryDays(input: string | number): string | null {
  const num = typeof input === 'number' ? input : Number(input);
  if (input === '' || Number.isNaN(num)) {
    return '请输入有效的临期天数';
  }
  if (!Number.isInteger(num)) {
    return '临期天数必须为整数';
  }
  if (num < NEAR_EXPIRY_DAYS_MIN || num > NEAR_EXPIRY_DAYS_MAX) {
    return `临期天数需在 ${NEAR_EXPIRY_DAYS_MIN} 到 ${NEAR_EXPIRY_DAYS_MAX} 天之间`;
  }
  return null;
}
