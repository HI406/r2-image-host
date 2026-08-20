import { success, error } from '../utils/response.js';
import {
  buildObjectKey,
  parseFormData,
  sanitizePath,
  validateFileSize,
  validateFileType,
  validateMagicNumber,
} from '../utils/validator.js';

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

/**
 * 验证 HTTP Basic Auth 凭证
 * 使用 APP_PASSWORD 作为用户名和密码（兼容简写：仅密码）
 * @param {Request} request - HTTP 请求对象
 * @param {string} appPassword - 应用密码
 * @returns {Response|null} 认证失败返回 401 Response，成功返回 null
 */
function verifyBasicAuth(request, appPassword) {
  const authHeader = request.headers.get('authorization') || '';
  if (!authHeader.startsWith('Basic ')) {
    return error('Missing or invalid Authorization header', 401);
  }

  const decoded = atob(authHeader.slice('Basic '.length).trim());
  // 支持两种格式："password" 或 "username:password"
  const password = decoded.includes(':') ? decoded.split(':').slice(1).join(':') : decoded;

  if (password !== appPassword) {
    return error('Invalid credentials', 401);
  }

  return null;
}

/**
 * POST /api/upload-direct
 * 直传图片 API，使用 HTTP Basic Auth 认证
 *
 * 请求：
 *   - Authorization: Basic base64(password) 或 Basic base64(user:password)
 *   - Content-Type: multipart/form-data
 *   - body: file=图片文件
 *   - query: ?webp=true 可选，启用 WebP 格式转换
 *
 * 成功响应：
 *   { success: true, data: { url, key, filename, size, type } }
 *
 * 失败响应：
 *   { success: false, error: "错误信息" }
 */
export async function handleDirectUpload(request, env) {
  // 1. 验证 Basic Auth
  const authError = verifyBasicAuth(request, env.APP_PASSWORD);
  if (authError) return authError;

  // 2. 解析表单数据
  let form;
  try {
    form = await parseFormData(request);
  } catch (err) {
    return error('Invalid form data');
  }

  const file = form.get('file');
  if (!(file instanceof File)) {
    return error('File is required');
  }

  const path = sanitizePath(form.get('path') || '');

  // 3. 校验文件
  try {
    validateFileType(file);
    validateFileSize(file, MAX_FILE_SIZE);
    await validateMagicNumber(file);
  } catch (err) {
    return error(err.message);
  }

  // 4. 检查是否需要 WebP 转换（通过 query 参数 ?webp=true）
  const url = new URL(request.url);
  const wantWebp = url.searchParams.get('webp') === 'true';

  let uploadFile = file;
  let contentType = file.type;
  let fileName = file.name || 'upload';

  // 如果请求 WebP 且文件不是 WebP，修改文件名后缀
  // 注意：Worker 端无法做真正的图片格式转换，需客户端预转换
  if (wantWebp && file.type !== 'image/webp') {
    const baseName = fileName.replace(/\.[^.]+$/, '');
    fileName = baseName + '.webp';
    contentType = 'image/webp';
  }

  // 5. 构建存储 key 并上传到 R2
  const key = buildObjectKey({ basePath: path, originalName: fileName });

  const metadata = {
    httpMetadata: {
      contentType,
      cacheControl: 'public, max-age=31536000',
    },
    customMetadata: {
      originalName: file.name,
      uploadTime: new Date().toISOString(),
      size: String(file.size),
      apiUpload: 'true',
    },
  };

  await env.R2_BUCKET.put(key, await uploadFile.arrayBuffer(), metadata);

  // 6. 返回直链 URL
  const publicDomain = env.R2_PUBLIC_DOMAIN || '';
  const directUrl = publicDomain ? `${publicDomain.replace(/\/$/, '')}/${key}` : null;

  return success({
    url: directUrl,
    key,
    filename: key.split('/').pop(),
    size: file.size,
    type: contentType,
  });
}
