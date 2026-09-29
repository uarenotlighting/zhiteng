import {
  Injectable,
  UnauthorizedException,
  BadRequestException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Platform, MembershipRole, SubjectKind } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AppConfigService } from '../config/app-config.service';
import {
  parseDurationToMs,
  randomToken,
  sha256,
} from '../common/crypto.util';
import { PlatformExchangeDto } from './dto/platform-exchange.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';

export type TokenPair = {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  tokenType: 'Bearer';
  user: {
    id: string;
    subjectId: string;
    platform: Platform;
  };
};

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: AppConfigService,
  ) {}

  async exchangePlatform(dto: PlatformExchangeDto): Promise<TokenPair> {
    const platform = dto.platform;
    const verified = await this.verifyPlatformCredential(platform, dto);

    return this.issueForPlatformIdentity({
      platform,
      platformUserId: verified.platformUserId,
      platformUnionId: verified.platformUnionId,
    });
  }

  async refresh(dto: RefreshTokenDto): Promise<TokenPair> {
    const hash = sha256(dto.refreshToken);
    const stored = await this.prisma.refreshToken.findFirst({
      where: { tokenHash: hash, revokedAt: null },
      include: { user: true },
    });

    if (!stored || stored.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException('Refresh token invalid or expired');
    }

    if (stored.user.status !== 'active') {
      throw new UnauthorizedException('User is not active');
    }

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });

    const identity = await this.prisma.platformIdentity.findFirst({
      where: { userId: stored.userId },
      orderBy: { boundAt: 'desc' },
    });

    const subject = await this.ensureSelfSubject(stored.userId);

    return this.issueTokens({
      userId: stored.userId,
      subjectId: subject.id,
      platform: identity?.platform ?? Platform.dev,
    });
  }

  private async verifyPlatformCredential(
    platform: Platform,
    dto: PlatformExchangeDto,
  ): Promise<{ platformUserId: string; platformUnionId?: string }> {
    if (platform === Platform.dev) {
      if (!this.config.authDevMockEnabled || !this.config.isDev) {
        throw new BadRequestException('Dev platform login is disabled');
      }
      if (!dto.devUserId) {
        throw new BadRequestException('devUserId is required for platform=dev');
      }
      return { platformUserId: dto.devUserId };
    }

    if (platform === Platform.weixin) {
      return this.verifyWeixin(dto.code);
    }

    // Douyin / Xiaohongshu adapters can plug in the same pattern later.
    if (this.config.authDevMockEnabled && this.config.isDev && dto.devUserId) {
      return { platformUserId: dto.devUserId };
    }

    throw new BadRequestException(
      `Platform ${platform} login is not configured yet`,
    );
  }

  private async verifyWeixin(
    code?: string,
  ): Promise<{ platformUserId: string; platformUnionId?: string }> {
    if (!code) {
      throw new BadRequestException('code is required for weixin login');
    }

    const appId = this.config.weixinAppId;
    const secret = this.config.weixinAppSecret;

    if (!appId || !secret) {
      if (this.config.authDevMockEnabled && this.config.isDev) {
        // Local development without real WeChat credentials.
        return { platformUserId: `wx_mock_${code}` };
      }
      throw new BadRequestException('Weixin credentials are not configured');
    }

    const url = new URL('https://api.weixin.qq.com/sns/jscode2session');
    url.searchParams.set('appid', appId);
    url.searchParams.set('secret', secret);
    url.searchParams.set('js_code', code);
    url.searchParams.set('grant_type', 'authorization_code');

    const response = await fetch(url);
    const data = (await response.json()) as {
      openid?: string;
      unionid?: string;
      errcode?: number;
      errmsg?: string;
    };

    if (!data.openid) {
      throw new UnauthorizedException(
        data.errmsg ?? 'Weixin code exchange failed',
      );
    }

    return {
      platformUserId: data.openid,
      platformUnionId: data.unionid,
    };
  }

  private async issueForPlatformIdentity(input: {
    platform: Platform;
    platformUserId: string;
    platformUnionId?: string;
  }): Promise<TokenPair> {
    const existing = await this.prisma.platformIdentity.findUnique({
      where: {
        platform_platformUserId: {
          platform: input.platform,
          platformUserId: input.platformUserId,
        },
      },
    });

    let userId: string;

    if (existing) {
      userId = existing.userId;
      if (input.platformUnionId && !existing.platformUnionId) {
        await this.prisma.platformIdentity.update({
          where: { id: existing.id },
          data: { platformUnionId: input.platformUnionId },
        });
      }
    } else {
      const created = await this.prisma.$transaction(async (tx) => {
        const user = await tx.user.create({ data: {} });
        await tx.platformIdentity.create({
          data: {
            userId: user.id,
            platform: input.platform,
            platformUserId: input.platformUserId,
            platformUnionId: input.platformUnionId,
          },
        });
        const subject = await tx.subject.create({
          data: {
            ownerId: user.id,
            kind: SubjectKind.self,
            displayName: '本人',
          },
        });
        await tx.subjectMembership.create({
          data: {
            subjectId: subject.id,
            userId: user.id,
            role: MembershipRole.owner,
          },
        });
        return { user, subject };
      });
      userId = created.user.id;
    }

    const subject = await this.ensureSelfSubject(userId);

    return this.issueTokens({
      userId,
      subjectId: subject.id,
      platform: input.platform,
    });
  }

  private async ensureSelfSubject(userId: string) {
    const existing = await this.prisma.subject.findFirst({
      where: { ownerId: userId, kind: SubjectKind.self },
      orderBy: { createdAt: 'asc' },
    });
    if (existing) return existing;

    return this.prisma.$transaction(async (tx) => {
      const subject = await tx.subject.create({
        data: {
          ownerId: userId,
          kind: SubjectKind.self,
          displayName: '本人',
        },
      });
      await tx.subjectMembership.create({
        data: {
          subjectId: subject.id,
          userId,
          role: MembershipRole.owner,
        },
      });
      return subject;
    });
  }

  private async issueTokens(input: {
    userId: string;
    subjectId: string;
    platform: Platform;
  }): Promise<TokenPair> {
    const accessExpiresMs = parseDurationToMs(this.config.jwtAccessTtl);
    const refreshExpiresMs = parseDurationToMs(this.config.jwtRefreshTtl);

    const accessToken = await this.jwt.signAsync(
      {
        sub: input.userId,
        subjectId: input.subjectId,
        platform: input.platform,
      },
      {
        secret: this.config.jwtAccessSecret,
        expiresIn: Math.floor(accessExpiresMs / 1000),
      },
    );

    const refreshToken = randomToken(48);
    await this.prisma.refreshToken.create({
      data: {
        userId: input.userId,
        tokenHash: sha256(refreshToken),
        expiresAt: new Date(Date.now() + refreshExpiresMs),
      },
    });

    return {
      accessToken,
      refreshToken,
      expiresIn: Math.floor(accessExpiresMs / 1000),
      tokenType: 'Bearer',
      user: {
        id: input.userId,
        subjectId: input.subjectId,
        platform: input.platform,
      },
    };
  }
}
