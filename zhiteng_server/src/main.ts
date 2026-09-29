import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { ValidationPipe, VersioningType } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AppConfigService } from './config/app-config.service';
import {
  TransportExceptionFilter,
  TransportResponseInterceptor,
} from './common/aes-transport';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  // AES 线上 body 为 text/plain（key + Base64）
  app.useBodyParser('text', { type: 'text/plain', limit: '2mb' });

  const config = app.get(AppConfigService);

  app.enableCors({
    origin: config.corsOrigins,
    credentials: true,
  });

  app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      validateCustomDecorators: true,
    }),
  );
  app.useGlobalInterceptors(new TransportResponseInterceptor());
  app.useGlobalFilters(new TransportExceptionFilter());

  const swagger = new DocumentBuilder()
    .setTitle('知疼 API')
    .setDescription(
      [
        '小程序 / App / Watch 共用后端。',
        '业务接口统一 POST + JSON 信封 `{ os, version, language, params }`；',
        '生产环境强制 AES-128-CBC 传输加密（与微光协议对齐）。',
        '开发默认明文；设 TRANSPORT_ENCRYPTION=true 可联调加密。',
      ].join(''),
    )
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swagger);
  SwaggerModule.setup('docs', app, document);

  await app.listen(config.port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`知疼 API listening on http://127.0.0.1:${config.port}`);
  // eslint-disable-next-line no-console
  console.log(`OpenAPI docs: http://127.0.0.1:${config.port}/docs`);
  // eslint-disable-next-line no-console
  console.log(
    `Transport encryption: ${
      process.env.NODE_ENV === 'production' ||
      process.env.TRANSPORT_ENCRYPTION === 'true'
        ? 'ON'
        : 'OFF (dev plaintext)'
    }`,
  );
}

void bootstrap();
