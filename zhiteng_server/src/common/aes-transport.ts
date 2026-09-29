import {
  BadRequestException,
  Catch,
  type ArgumentsHost,
  type CallHandler,
  type ExceptionFilter,
  HttpException,
  Injectable,
  type NestInterceptor,
  StreamableFile,
  type ExecutionContext,
} from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import type { Request, Response } from 'express';
import { map, type Observable } from 'rxjs';
import { isTransportEncryptionEnabled } from './transport-mode';
import { isPublicPlaintextGet } from './public-plaintext-get-path';

const AES_IV = Buffer.from('hj6cdzrhj72x8ht1', 'utf8');
const REQUEST_MARKER = 'AAA##';

function randomTransportKey() {
  return randomBytes(8).toString('hex');
}

function encryptBuffer(buffer: Buffer, key: string) {
  const cipher = createCipheriv(
    'aes-128-cbc',
    Buffer.from(key, 'utf8'),
    AES_IV,
  );
  return Buffer.concat([cipher.update(buffer), cipher.final()]).toString(
    'base64',
  );
}

function decryptBuffer(ciphertext: string, key: string) {
  try {
    const decipher = createDecipheriv(
      'aes-128-cbc',
      Buffer.from(key, 'utf8'),
      AES_IV,
    );
    return Buffer.concat([
      decipher.update(Buffer.from(ciphertext, 'base64')),
      decipher.final(),
    ]);
  } catch {
    throw new BadRequestException('请求参数解密失败');
  }
}

function splitPayload(payload: unknown) {
  if (typeof payload !== 'string' || payload.length <= 16) {
    throw new BadRequestException('请求缺少 AES 加密数据');
  }
  return { key: payload.slice(0, 16), ciphertext: payload.slice(16) };
}

export function decryptRequestPayload(payload: unknown): unknown {
  const encrypted =
    payload && typeof payload === 'object' && !Array.isArray(payload)
      ? (payload as { data?: unknown }).data
      : payload;
  const { key, ciphertext } = splitPayload(encrypted);
  const plaintext = decryptBuffer(ciphertext, key).toString('utf8');
  if (!plaintext.startsWith(REQUEST_MARKER)) {
    throw new BadRequestException('请求参数校验失败');
  }
  try {
    return JSON.parse(plaintext.slice(REQUEST_MARKER.length));
  } catch {
    throw new BadRequestException('请求参数不是有效 JSON');
  }
}

export function encryptRequestPayload(value: unknown) {
  const key = randomTransportKey();
  const plaintext = Buffer.from(
    `${REQUEST_MARKER}${JSON.stringify(value)}`,
    'utf8',
  );
  return `${key}${encryptBuffer(plaintext, key)}`;
}

export function encryptResponsePayload(value: unknown) {
  const key = randomTransportKey();
  return `${key}${encryptBuffer(
    Buffer.from(JSON.stringify(value ?? null), 'utf8'),
    key,
  )}`;
}

export function decryptResponsePayload<T>(payload: unknown): T {
  const { key, ciphertext } = splitPayload(payload);
  try {
    return JSON.parse(decryptBuffer(ciphertext, key).toString('utf8')) as T;
  } catch (error) {
    if (error instanceof HttpException) throw error;
    throw new BadRequestException('响应数据解密失败');
  }
}

@Injectable()
export class TransportResponseInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    const response = context.switchToHttp().getResponse<Response>();
    const path = (request.originalUrl || request.url).split('?')[0];
    if (isPublicPlaintextGet(path, request.method)) return next.handle();
    return next.handle().pipe(
      map((value) => {
        if (value instanceof StreamableFile) return value;
        if (isTransportEncryptionEnabled()) {
          response.type('text/plain');
          return encryptResponsePayload(value);
        }
        response.type('application/json');
        return value ?? null;
      }),
    );
  }
}

@Catch()
export class TransportExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    const request = host.switchToHttp().getRequest<Request>();
    const status =
      exception instanceof HttpException ? exception.getStatus() : 500;
    if (!(exception instanceof HttpException)) {
      // eslint-disable-next-line no-console
      console.error(
        JSON.stringify({
          event: 'unhandled_exception',
          method: request.method,
          path: request.path,
          errorType:
            exception instanceof Error
              ? exception.constructor.name
              : typeof exception,
        }),
      );
    }
    const detail =
      exception instanceof HttpException
        ? exception.getResponse()
        : { message: '服务器内部错误' };
    const body =
      typeof detail === 'string'
        ? { statusCode: status, message: detail, path: request.path }
        : { statusCode: status, ...detail, path: request.path };
    if (
      isTransportEncryptionEnabled() &&
      !isPublicPlaintextGet(
        (request.originalUrl || request.url).split('?')[0],
        request.method,
      )
    ) {
      response
        .status(status)
        .type('text/plain')
        .send(encryptResponsePayload(body));
      return;
    }
    response.status(status).json(body);
  }
}
