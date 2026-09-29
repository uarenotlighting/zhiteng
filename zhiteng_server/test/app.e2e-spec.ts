import { Test, TestingModule } from '@nestjs/testing';
import {
  INestApplication,
  ValidationPipe,
  VersioningType,
} from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module';
import {
  TransportExceptionFilter,
  TransportResponseInterceptor,
} from './../src/common/aes-transport';

describe('Protocol (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        validateCustomDecorators: true,
      }),
    );
    app.useGlobalInterceptors(new TransportResponseInterceptor());
    app.useGlobalFilters(new TransportExceptionFilter());
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('GET /v1/health plaintext', () => {
    return request(app.getHttpServer()).get('/v1/health').expect(200);
  });

  it('POST /v1/auth/platform/exchange envelope', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/platform/exchange')
      .send({
        os: 'ios',
        version: '1.0.0',
        language: 'zh-CN',
        params: {
          user_id: '',
          platform: 'dev',
          devUserId: 'e2e-user',
        },
      })
      .expect(201);
    expect(res.body.accessToken).toBeTruthy();
  });
});
