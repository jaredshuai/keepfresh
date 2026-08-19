# Task 4 Brief: 封装 OCR 识别与照片选择服务 (`OcrService.ets`)

## Files
- Create: `entry/src/main/ets/service/OcrService.ets`

## Requirements
1. Create `entry/src/main/ets/service/OcrService.ets`:
   - Import necessary modules:
     ```typescript
     import { common } from '@kit.AbilityKit';
     import { photoAccessHelper } from '@kit.MediaLibraryKit';
     import { textRecognition } from '@kit.CoreVisionKit';
     import { image } from '@kit.ImageKit';
     import { fileIo as fs } from '@kit.CoreFileKit';
     import { BusinessError } from '@kit.BasicServicesKit';
     import { hilog } from '@kit.PerformanceAnalysisKit';
     import { parseDateFromText, ParsedDateResult } from './DateTextParser';
     ```
   - Export function `pickAndRecognizeDate(context: common.UIAbilityContext): Promise<ParsedDateResult | undefined>`:
     - 1. Open photo picker with `PhotoSelectOptions` (`MIMEType: IMAGE_TYPE`, `maxSelectNumber: 1`).
     - 2. Retrieve selected image URI. If cancelled/no URI, return `undefined`.
     - 3. Read image file via `fs.openSync(uri, fs.OpenMode.READ_ONLY)` -> `image.createImageSource(file.fd).createPixelMap()`, ensure `fs.closeSync(file)` in `finally`.
     - 4. Recognize text with `textRecognition.recognizeText({ pixelMap })`, ensure `pixelMap.release()` in `finally`.
     - 5. Handle errors gracefully with try/catch and logging.
     - 6. If recognized text lines exist, pipe text through `parseDateFromText(textLines)` and return the `ParsedDateResult`.
     - 7. If no text or unrecognized, return `{ rawMatchedText: [] }`.
2. Commit the changes:
   - Commit message: `feat(service): implement CoreVisionKit OCR date extraction service`
