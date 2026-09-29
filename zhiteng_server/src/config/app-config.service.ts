import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class AppConfigService {
  constructor(private readonly config: ConfigService) {}

  get nodeEnv(): string {
    return this.config.get<string>('NODE_ENV', 'development');
  }

  get isDev(): boolean {
    return this.nodeEnv !== 'production';
  }

  get port(): number {
    return Number(this.config.get<string>('PORT', '3000'));
  }

  get apiPrefix(): string {
    return this.config.get<string>('API_PREFIX', 'v1');
  }

  get databaseUrl(): string {
    return this.config.getOrThrow<string>('DATABASE_URL');
  }

  get redisUrl(): string {
    return this.config.get<string>('REDIS_URL', 'redis://127.0.0.1:6379');
  }

  get jwtAccessSecret(): string {
    return this.config.getOrThrow<string>('JWT_ACCESS_SECRET');
  }

  get jwtRefreshSecret(): string {
    return this.config.getOrThrow<string>('JWT_REFRESH_SECRET');
  }

  get jwtAccessTtl(): string {
    return this.config.get<string>('JWT_ACCESS_TTL', '15m');
  }

  get jwtRefreshTtl(): string {
    return this.config.get<string>('JWT_REFRESH_TTL', '30d');
  }

  get authDevMockEnabled(): boolean {
    return this.config.get<string>('AUTH_DEV_MOCK_ENABLED', 'true') === 'true';
  }

  get weixinAppId(): string | undefined {
    return this.config.get<string>('WEIXIN_APP_ID') || undefined;
  }

  get weixinAppSecret(): string | undefined {
    return this.config.get<string>('WEIXIN_APP_SECRET') || undefined;
  }

  get corsOrigins(): string[] | boolean {
    const raw = this.config.get<string>('CORS_ORIGINS', '');
    if (!raw.trim()) {
      return this.isDev ? true : false;
    }
    return raw.split(',').map((s) => s.trim()).filter(Boolean);
  }
}
