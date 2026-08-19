# Task 2 Brief: 智能日期与保质期文本抽取引擎 (`DateTextParser.ets`)

## Files
- Create: `entry/src/main/ets/service/DateTextParser.ets`
- Create / Run verification tests (e.g. Node/ArkTS test script)

## Requirements
1. Create `entry/src/main/ets/service/DateTextParser.ets`:
   - Export `interface ParsedDateResult`:
     ```typescript
     export interface ParsedDateResult {
       productionDate?: string;     // YYYY-MM-DD
       shelfLifeDays?: number;      // 天数
       expiryDate?: string;          // YYYY-MM-DD
       rawMatchedText: string[];
     }
     ```
   - Export `parseDateFromText(input: string | string[]): ParsedDateResult`.
   - Matching rules:
     - 生产日期前缀匹配: `(?:生产日期|PROD|MFG|PD)[:：\s]*([12]\d{3})[-/.年\s]?(\d{1,2})[-/.月\s]?(\d{1,2})日?`
     - 到期日/保质期至前缀匹配: `(?:保质期至|到期日|失效期|EXP|USE BY|BEST BEFORE)[:：\s]*([12]\d{3})[-/.年\s]?(\d{1,2})[-/.月\s]?(\d{1,2})日?`
     - 通用日期匹配 (当没有前缀时): `([12]\d{3})[-/.年](\d{1,2})[-/.月](\d{1,2})` or `\b(20\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\b`
     - 保质期时长匹配:
       - `(?:保质期|保质期限)[:：\s]*(\d+)\s*(个?月|天|日|年|months?|days?|years?)`
       - 独立时长: `(\d+)\s*(个?月|天|日|年)` (月->num*30, 年->num*365, 天->num)
     - 联动推导:
       - 若匹配到生产日期 + 保质期时长，自动推导到期日 (`addDays(productionDate, shelfLifeDays)`)
       - 若匹配到生产日期 + 到期日，自动反算保质期天数 (`diffDays(productionDate, expiryDate)`)
       - 若匹配到到期日 + 保质期时长，自动反算生产日期 (`addDays(expiryDate, -shelfLifeDays)`)
     - 合法性校验 (年份范围比如 2020~2035, 月份 1~12, 日 1~31)
2. Test / Verify:
   - Verify parsing across all formats (e.g. `生产日期: 2026-05-12 保质期: 12个月`, `EXP: 2027/01/01`, `20260819 180天`, `2026年5月10日`)
3. Commit the changes:
   - Commit message: `feat(service): implement smart date and shelf-life text extraction engine`
