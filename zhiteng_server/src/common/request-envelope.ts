import {
  BadRequestException,
  createParamDecorator,
  type ExecutionContext,
} from '@nestjs/common';
import { decryptRequestPayload } from './aes-transport';
import { isTransportEncryptionEnabled } from './transport-mode';

const DECRYPTED_ENVELOPE = Symbol('decrypted-envelope');

export type RequestEnvelope<T extends object = Record<string, unknown>> = {
  os: string;
  version: string;
  language: string;
  params: T;
};

function parseParams(value: unknown): Record<string, unknown> {
  if (typeof value === 'string') {
    try {
      const parsed: unknown = JSON.parse(value);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // Fall through.
    }
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  throw new BadRequestException('请求 params 必须是对象');
}

function decodePlainRequestPayload(payload: unknown) {
  const value =
    payload && typeof payload === 'object' && !Array.isArray(payload)
      ? ((payload as { data?: unknown }).data ?? payload)
      : payload;
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value) as unknown;
  } catch {
    throw new BadRequestException('请求体不是有效 JSON');
  }
}

type ParsedRequestEnvelope = {
  language: string;
  params: Record<string, unknown>;
};

function resolveRequestEnvelope(request: {
  body?: unknown;
  [DECRYPTED_ENVELOPE]?: unknown;
}): ParsedRequestEnvelope {
  const cached = request[DECRYPTED_ENVELOPE];
  if (cached && typeof cached === 'object' && !Array.isArray(cached)) {
    const envelope = cached as Partial<RequestEnvelope>;
    const params = parseParams(envelope.params);
    if (typeof params.user_id !== 'string') {
      throw new BadRequestException('请求 params 缺少 user_id');
    }
    return {
      language:
        typeof envelope.language === 'string' ? envelope.language : 'zh-CN',
      params,
    };
  }

  const body = isTransportEncryptionEnabled()
    ? decryptRequestPayload(request.body)
    : decodePlainRequestPayload(request.body);
  request[DECRYPTED_ENVELOPE] = body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new BadRequestException('请求体格式不正确');
  }
  const envelope = body as Partial<RequestEnvelope>;
  if (
    typeof envelope.os !== 'string' ||
    !envelope.os ||
    typeof envelope.version !== 'string' ||
    !envelope.version ||
    typeof envelope.language !== 'string' ||
    !envelope.language
  ) {
    throw new BadRequestException('请求缺少 os、version 或 language');
  }
  const params = parseParams(envelope.params);
  if (typeof params.user_id !== 'string') {
    throw new BadRequestException('请求 params 缺少 user_id');
  }
  return {
    language: envelope.language,
    params,
  };
}

/**
 * Reads the shared client envelope while still allowing Nest's ValidationPipe
 * to validate and transform the returned DTO (validateCustomDecorators: true).
 */
export const RequestParams = createParamDecorator(
  (key: string | undefined, context: ExecutionContext) => {
    const request = context.switchToHttp().getRequest<{
      body?: unknown;
      [DECRYPTED_ENVELOPE]?: unknown;
    }>();
    const { params } = resolveRequestEnvelope(request);
    return key ? params[key] : params;
  },
);
