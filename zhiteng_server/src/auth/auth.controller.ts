import { Controller, Post } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { PlatformExchangeDto } from './dto/platform-exchange.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { Public } from '../common/auth.decorators';
import { RequestParams } from '../common/request-envelope';

@ApiTags('auth')
@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('platform/exchange')
  @ApiOperation({
    summary: '用平台登录凭证换取知疼 Access/Refresh Token',
    description:
      '统一 POST 信封。开发模式可用 platform=dev + devUserId；微信未配置密钥时也会走 mock。',
  })
  exchange(@RequestParams() dto: PlatformExchangeDto) {
    return this.auth.exchangePlatform(dto);
  }

  @Public()
  @Post('refresh')
  @ApiOperation({ summary: '刷新 Access Token（Refresh Token 轮换）' })
  refresh(@RequestParams() dto: RefreshTokenDto) {
    return this.auth.refresh(dto);
  }
}
