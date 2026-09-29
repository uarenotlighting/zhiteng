import { Controller, Get, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../common/auth.decorators';
import { EmptyParamsDto } from '../common/dto/envelope-base.dto';
import { RequestParams } from '../common/request-envelope';
import { PrismaService } from '../prisma/prisma.service';

@ApiTags('health')
@Controller({ path: 'health', version: '1' })
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  /** 明文 GET，供探针 / 运维使用（不走统一信封） */
  @Public()
  @Get()
  async checkGet() {
    return this.check();
  }

  /** 统一 POST 信封，与业务协议一致 */
  @Public()
  @Post()
  async checkPost(@RequestParams() _params: EmptyParamsDto) {
    return this.check();
  }

  private async check() {
    await this.prisma.$queryRaw`SELECT 1`;
    return {
      ok: true,
      service: 'zhiteng-server',
      time: new Date().toISOString(),
    };
  }
}
