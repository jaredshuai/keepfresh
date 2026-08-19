/**
 * 智能日期与保质期文本抽取引擎
 * 从 OCR 识别出的原始文本或行列表中提取生产日期、到期日、保质期时长并进行联动推导。
 */

import { addDays, diffDays, pad2, todayStr } from '../common/DateUtils';

export interface ParsedDateResult {
  productionDate?: string;     // 生产日期 (YYYY-MM-DD)
  shelfLifeDays?: number;      // 保质期天数
  expiryDate?: string;         // 到期日期 (YYYY-MM-DD)
  rawMatchedText: string[];    // 命中匹配的原始文本片段
}

interface SpanMatch {
  start: number;
  end: number;
  type: 'prod' | 'expiry' | 'shelflife' | 'generic';
  text: string;
}

interface TextSpan {
  start: number;
  end: number;
}

interface GenericDateItem {
  dateStr: string;
  raw: string;
  start: number;
  end: number;
}

/**
 * 将全角字符（如全角数字、冒号、斜杠等）转半角，方便统一正则解析
 */
function normalizeText(text: string): string {
  let res = '';
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0xFF01 && code <= 0xFF5E) {
      res += String.fromCharCode(code - 0xFEE0);
    } else if (code === 0x3000) {
      res += ' ';
    } else {
      res += text[i];
    }
  }
  return res;
}

/**
 * 校验公历日期的合法性（支持 1990 ~ 2099 年）
 */
function isValidDate(year: number, month: number, day: number): boolean {
  if (year < 1990 || year > 2099 || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  const d = new Date(year, month - 1, day);
  return d.getFullYear() === year && (d.getMonth() + 1) === month && d.getDate() === day;
}

/**
 * 格式化为标准 YYYY-MM-DD
 */
function formatFormattedDate(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

/**
 * 将提取到的保质期数字与单位换算为天数
 */
function parseShelfLifeToDays(numStr: string, unitStr: string): number {
  const num = parseFloat(numStr);
  if (isNaN(num) || num <= 0) {
    return 0;
  }
  const unit = unitStr.toLowerCase();
  if (unit.includes('年') || unit.startsWith('y')) {
    return Math.round(num * 365);
  }
  if (unit.includes('月') || unit.startsWith('m')) {
    return Math.round(num * 30);
  }
  if (unit.includes('天') || unit.includes('日') || unit.startsWith('d')) {
    return Math.round(num);
  }
  return Math.round(num);
}

/**
 * 检查文本区间是否与已有匹配重叠
 */
function isOverlap(start: number, end: number, spans: TextSpan[]): boolean {
  for (let i = 0; i < spans.length; i++) {
    const s = spans[i];
    if (start < s.end && end > s.start) {
      return true;
    }
  }
  return false;
}

/**
 * 从文本或字符串数组中抽取日期与保质期信息
 * @param input 待解析的 OCR 原始文本或字符串行数组
 * @returns ParsedDateResult 抽取并联动推导的结果
 */
export function parseDateFromText(input: string | string[]): ParsedDateResult {
  const rawText: string = Array.isArray(input) ? input.join('\n') : (input || '');
  const text: string = normalizeText(rawText);

  let productionDate: string | undefined = undefined;
  let expiryDate: string | undefined = undefined;
  let shelfLifeDays: number | undefined = undefined;
  const rawMatchedText: string[] = [];
  const spans: SpanMatch[] = [];

  const addMatch = (raw: string, start: number, end: number, type: 'prod' | 'expiry' | 'shelflife' | 'generic'): void => {
    const trimmed = raw.trim();
    if (trimmed.length > 0 && !rawMatchedText.includes(trimmed)) {
      rawMatchedText.push(trimmed);
    }
    spans.push({ start, end, type, text: raw });
  };

  // Pass 1: 带前缀的生产日期
  // 1.1 分隔符形式 (如 生产日期: 2026-05-12 / 2026.05.12 / 2026/05/12 / 2026年05月12日)
  const prodDelimRegex = /(?:生产日期|生产日|制造日期|制作日期|出厂日期|包装日期|生产|PROD(?:UCTION)?(?:\s*DATE)?|MFG(?:\s*DATE)?|PD|MFD|PRD|DOM|PKD)[\s:：#№=-]*([12]\d{3})\s*[-/.年\s]\s*(\d{1,2})\s*[-/.月\s]\s*(\d{1,2})(?:日|号)?/gi;
  let m: RegExpExecArray | null = null;
  while ((m = prodDelimRegex.exec(text)) !== null) {
    const y = parseInt(m[1], 10);
    const mth = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (isValidDate(y, mth, d) && !isOverlap(m.index, m.index + m[0].length, spans)) {
      if (!productionDate) {
        productionDate = formatFormattedDate(y, mth, d);
      }
      addMatch(m[0], m.index, m.index + m[0].length, 'prod');
    }
  }

  // 1.2 8位紧凑格式 (如 PROD: 20260512)
  const prodCompactRegex = /(?:生产日期|生产日|制造日期|制作日期|出厂日期|包装日期|生产|PROD(?:UCTION)?(?:\s*DATE)?|MFG(?:\s*DATE)?|PD|MFD|PRD|DOM|PKD)[\s:：#№=-]*(?<!\d)([12]\d{3})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)/gi;
  while ((m = prodCompactRegex.exec(text)) !== null) {
    const y = parseInt(m[1], 10);
    const mth = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (isValidDate(y, mth, d) && !isOverlap(m.index, m.index + m[0].length, spans)) {
      if (!productionDate) {
        productionDate = formatFormattedDate(y, mth, d);
      }
      addMatch(m[0], m.index, m.index + m[0].length, 'prod');
    }
  }

  // Pass 2: 带前缀的到期日 / 保质期至
  // 2.1 分隔符形式 (如 保质期至: 2026/12/31, EXP: 2027/01/01)
  const expiryDelimRegex = /(?:保质期至|保质期到|到期日期|到期日|到期|失效日期|失效期|有效(?:期|日期)至|有效(?:期|日期)到|截止日期|最佳食用日期|赏味期限|EXP(?:IRY)?(?:\s*DATE)?|USE\s*BY|BEST\s*BEFORE|BBD|BB|ED)[\s:：#№=-]*([12]\d{3})\s*[-/.年\s]\s*(\d{1,2})\s*[-/.月\s]\s*(\d{1,2})(?:日|号)?/gi;
  while ((m = expiryDelimRegex.exec(text)) !== null) {
    const y = parseInt(m[1], 10);
    const mth = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (isValidDate(y, mth, d) && !isOverlap(m.index, m.index + m[0].length, spans)) {
      if (!expiryDate) {
        expiryDate = formatFormattedDate(y, mth, d);
      }
      addMatch(m[0], m.index, m.index + m[0].length, 'expiry');
    }
  }

  // 2.2 8位紧凑格式 (如 EXP 20270101)
  const expiryCompactRegex = /(?:保质期至|保质期到|到期日期|到期日|到期|失效日期|失效期|有效(?:期|日期)至|有效(?:期|日期)到|截止日期|最佳食用日期|赏味期限|EXP(?:IRY)?(?:\s*DATE)?|USE\s*BY|BEST\s*BEFORE|BBD|BB|ED)[\s:：#№=-]*(?<!\d)([12]\d{3})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)/gi;
  while ((m = expiryCompactRegex.exec(text)) !== null) {
    const y = parseInt(m[1], 10);
    const mth = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (isValidDate(y, mth, d) && !isOverlap(m.index, m.index + m[0].length, spans)) {
      if (!expiryDate) {
        expiryDate = formatFormattedDate(y, mth, d);
      }
      addMatch(m[0], m.index, m.index + m[0].length, 'expiry');
    }
  }

  // Pass 3: 带前缀的保质期时长 (如 保质期: 12个月, SHELF LIFE: 180 DAYS)
  const shelfLifePrefixRegex = /(?:保质期(?:限)?|保存期(?:限)?|有效期(?:限)?|SHELF[\s_]*LIFE|EXPIRY)[\s:：#№=-]*(\d+(?:\.\d+)?)\s*(个?月|天|日|年|months?|days?|years?|\b[mdy]\b)(?![a-zA-Z\d])/gi;
  while ((m = shelfLifePrefixRegex.exec(text)) !== null) {
    const start = m.index;
    const end = m.index + m[0].length;
    if (!isOverlap(start, end, spans)) {
      const days = parseShelfLifeToDays(m[1], m[2]);
      if (days > 0) {
        if (shelfLifeDays === undefined) {
          shelfLifeDays = days;
        }
        addMatch(m[0], start, end, 'shelflife');
      }
    }
  }

  // Pass 4: 独立通用日期匹配 (未带前缀的日期候选)
  const genericDelimRegex = /(?<!\d)([12]\d{3})\s*[-/.年\s]\s*(\d{1,2})\s*[-/.月\s]\s*(\d{1,2})(?:日|号)?(?!\d)/gi;
  const genericDates: GenericDateItem[] = [];
  while ((m = genericDelimRegex.exec(text)) !== null) {
    const start = m.index;
    const end = m.index + m[0].length;
    const y = parseInt(m[1], 10);
    const mth = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (isValidDate(y, mth, d) && !isOverlap(start, end, spans)) {
      genericDates.push({
        dateStr: formatFormattedDate(y, mth, d),
        raw: m[0],
        start,
        end
      });
    }
  }

  const genericCompactRegex = /(?<!\d)([12]\d{3})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)/gi;
  while ((m = genericCompactRegex.exec(text)) !== null) {
    const start = m.index;
    const end = m.index + m[0].length;
    const y = parseInt(m[1], 10);
    const mth = parseInt(m[2], 10);
    const d = parseInt(m[3], 10);
    if (isValidDate(y, mth, d) && !isOverlap(start, end, spans)) {
      if (!genericDates.some((g: GenericDateItem) => isOverlap(start, end, [{ start: g.start, end: g.end }]))) {
        genericDates.push({
          dateStr: formatFormattedDate(y, mth, d),
          raw: m[0],
          start,
          end
        });
      }
    }
  }

  // 临时记录所有已识别的日期区间，避免独立保质期识别错误截取日期中的数字
  const tempDateSpans: TextSpan[] = [
    ...spans,
    ...genericDates.map((g: GenericDateItem): TextSpan => ({ start: g.start, end: g.end }))
  ];

  // Pass 5: 独立保质期时长 (如 "180天", "12个月")
  if (shelfLifeDays === undefined) {
    const standaloneShelfRegex = /(?<!\d)(\d+(?:\.\d+)?)\s*(个?月|天|日|年|months?|days?|years?)(?![a-zA-Z\d])/gi;
    while ((m = standaloneShelfRegex.exec(text)) !== null) {
      const start = m.index;
      const end = m.index + m[0].length;
      const num = parseFloat(m[1]);
      const unit = m[2];

      // 避免误匹配 2026年 中的年份
      if (unit.includes('年') && num > 100) {
        continue;
      }
      if (!isOverlap(start, end, tempDateSpans)) {
        const days = parseShelfLifeToDays(m[1], m[2]);
        if (days > 0) {
          shelfLifeDays = days;
          addMatch(m[0], start, end, 'shelflife');
          break;
        }
      }
    }
  }

  // 处理通用日期候选
  if (genericDates.length > 0) {
    if (!productionDate && !expiryDate) {
      if (genericDates.length >= 2) {
        // 存在多个独立日期时按先后排序，前为生产日期，后为到期日
        const sorted = [...genericDates].sort((a: GenericDateItem, b: GenericDateItem) => a.dateStr.localeCompare(b.dateStr));
        productionDate = sorted[0].dateStr;
        expiryDate = sorted[1].dateStr;
        addMatch(sorted[0].raw, sorted[0].start, sorted[0].end, 'generic');
        addMatch(sorted[1].raw, sorted[1].start, sorted[1].end, 'generic');
      } else {
        // 单个独立日期默认作为生产日期（符合商品喷码常规）
        productionDate = genericDates[0].dateStr;
        addMatch(genericDates[0].raw, genericDates[0].start, genericDates[0].end, 'generic');
      }
    } else if (productionDate && !expiryDate) {
      const candidate = genericDates.find((g: GenericDateItem) => g.dateStr >= (productionDate as string)) || genericDates[0];
      expiryDate = candidate.dateStr;
      addMatch(candidate.raw, candidate.start, candidate.end, 'generic');
    } else if (!productionDate && expiryDate) {
      const candidate = genericDates.find((g: GenericDateItem) => g.dateStr <= (expiryDate as string)) || genericDates[0];
      productionDate = candidate.dateStr;
      addMatch(candidate.raw, candidate.start, candidate.end, 'generic');
    }
  }

  // Pass 6: 双向联动推导
  // 6.1 生产日期 + 保质期时长 -> 到期日
  if (productionDate && shelfLifeDays !== undefined && !expiryDate) {
    expiryDate = addDays(productionDate, shelfLifeDays);
  }
  // 6.2 到期日 + 保质期时长 -> 反推生产日期
  else if (expiryDate && shelfLifeDays !== undefined && !productionDate) {
    productionDate = addDays(expiryDate, -shelfLifeDays);
  }
  // 6.3 生产日期 + 到期日 -> 计算保质期天数
  else if (productionDate && expiryDate && shelfLifeDays === undefined) {
    shelfLifeDays = Math.abs(diffDays(expiryDate, productionDate));
  }
  // 6.4 仅匹配到到期日 -> 默认将生产日期设为今天，天数设为距到期日的差值（若为正数）
  else if (!productionDate && expiryDate && shelfLifeDays === undefined) {
    const today = todayStr();
    const diff = diffDays(expiryDate, today);
    if (diff > 0) {
      productionDate = today;
      shelfLifeDays = diff;
    }
  }

  return {
    productionDate,
    shelfLifeDays,
    expiryDate,
    rawMatchedText
  };
}
