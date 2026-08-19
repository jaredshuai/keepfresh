/**
 * OCR 识别与照片选择服务：
 * 通过系统 PhotoViewPicker 选取包装喷码图片，利用 CoreVisionKit 进行端侧文字识别，
 * 并交由 DateTextParser 提取生产日期、到期日与保质期信息。
 */
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { parseDateFromText, ParsedDateResult } from './DateTextParser';

const DOMAIN: number = 0x0000;
const TAG: string = 'OcrService';

/**
 * 唤起系统相册选择包装特写图片并执行 OCR 文字识别与日期抽取
 * @param context UIAbility 上下文
 * @returns 抽取得到的日期与保质期结果，若用户取消选择或无选图则返回 undefined
 */
export async function pickAndRecognizeDate(
  context: common.UIAbilityContext
): Promise<ParsedDateResult | undefined> {
  // 1. 打开系统照片选择器选取包装喷码特写
  const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
  photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  photoSelectOptions.maxSelectNumber = 1;

  const photoPicker = new photoAccessHelper.PhotoViewPicker();
  let selectResult: photoAccessHelper.PhotoSelectResult;
  try {
    selectResult = await photoPicker.select(photoSelectOptions);
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'PhotoViewPicker select failed: %{public}s, code: %{public}d', e.message, e.code);
    return undefined;
  }

  if (!selectResult || !selectResult.photoUris || selectResult.photoUris.length === 0) {
    return undefined;
  }

  const uri = selectResult.photoUris[0];
  if (!uri) {
    return undefined;
  }

  // 2. 读取图片并转化为 PixelMap
  let pixelMap: image.PixelMap | undefined = undefined;
  let file: fs.File | undefined = undefined;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const imageSource = image.createImageSource(file.fd);
    pixelMap = await imageSource.createPixelMap();
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'Read image pixelMap failed: %{public}s, code: %{public}d', e.message, e.code);
    throw new Error(`读取图片失败: ${e.message || e.code}`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (closeErr) {
        hilog.warn(DOMAIN, TAG, 'Close file failed: %{public}s', JSON.stringify(closeErr));
      }
    }
  }

  if (!pixelMap) {
    throw new Error('无法解码图片');
  }

  // 3. 调用 CoreVisionKit 文字识别
  let textLines: string[] = [];
  try {
    const visionImage: textRecognition.VisionInfo = {
      pixelMap: pixelMap
    };
    const recognitionResult: textRecognition.VisionText = await textRecognition.recognizeText(visionImage);
    if (recognitionResult && recognitionResult.value) {
      const textVal = recognitionResult.value.trim();
      if (textVal.length > 0) {
        textLines.push(textVal);
      }
    }
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'textRecognition recognizeText failed: %{public}s, code: %{public}d', e.message, e.code);
    throw new Error(`文字识别失败: ${e.message || e.code}`);
  } finally {
    try {
      await pixelMap.release();
    } catch (relErr) {
      hilog.warn(DOMAIN, TAG, 'Release pixelMap failed: %{public}s', JSON.stringify(relErr));
    }
  }

  if (textLines.length === 0) {
    return {
      rawMatchedText: []
    };
  }

  // 4. 正则抽取日期与保质期
  return parseDateFromText(textLines);
}
