# Task 4 Report: 封装 OCR 识别与照片选择服务 (`OcrService.ets`)

## 1. Task Overview
- **Objective**: Implement photo selection via PhotoViewPicker (`@kit.MediaLibraryKit`) and on-device text recognition via CoreVisionKit (`@kit.CoreVisionKit`), integrated with DateTextParser for date & shelf-life extraction.
- **File Created**: `entry/src/main/ets/service/OcrService.ets`

## 2. Implementation Summary
- **Service Logic**:
  - `pickAndRecognizeDate(context: common.UIAbilityContext): Promise<ParsedDateResult | undefined>`:
    1. Invokes `photoAccessHelper.PhotoViewPicker` with `PhotoSelectOptions` (`IMAGE_TYPE`, `maxSelectNumber: 1`) to pick package photo. Gracefully returns `undefined` if user cancels or no image selected.
    2. Opens image file descriptor via `fs.openSync(uri, fs.OpenMode.READ_ONLY)` and creates `PixelMap` using `image.createImageSource(file.fd).createPixelMap()`, ensuring `file` is closed safely in a `finally` block.
    3. Runs on-device text recognition via `textRecognition.recognizeText({ pixelMap })`, ensuring `pixelMap.release()` in a `finally` block.
    4. Passes recognized text into `parseDateFromText(textLines)` to extract production date, expiry date, shelf life, and raw matched text.
    5. Returns `{ rawMatchedText: [] }` if no text is recognized or recognized text is empty.
    6. Structured logging with `hilog` (`DOMAIN: 0x0000`, `TAG: 'OcrService'`) and robust error handling.

## 3. Verification & Git Commit
- **Type/Syntax Check**: Conforms strictly to ArkTS specifications, HarmonyOS NEXT kits (`@kit.CoreVisionKit`, `@kit.MediaLibraryKit`, `@kit.ImageKit`, `@kit.CoreFileKit`, `@kit.AbilityKit`), and project architecture.
- **Git Commit**:
  - `b2d998b feat(service): implement CoreVisionKit OCR date extraction service`

## 4. Status
- **Status**: Completed
