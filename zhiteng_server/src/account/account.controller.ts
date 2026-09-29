import { Controller, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/auth.decorators';
import type { AuthUser } from '../common/auth.decorators';
import { EmptyParamsDto } from '../common/dto/envelope-base.dto';
import { RequestParams } from '../common/request-envelope';
import { AccountService } from './account.service';

@ApiTags('account')
@ApiBearerAuth()
@Controller({ path: 'account', version: '1' })
export class AccountController {
  constructor(private readonly account: AccountService) {}

  @Post('me')
  @ApiOperation({ summary: '当前登录用户与本人 Subject' })
  me(
    @CurrentUser() user: AuthUser,
    @RequestParams() _params: EmptyParamsDto,
  ) {
    return this.account.getMe(user);
  }

  @Post('health-data/delete')
  @ApiOperation({
    summary: '删除当前用户全部健康数据（保留账号壳）',
  })
  deleteHealthData(
    @CurrentUser() user: AuthUser,
    @RequestParams() _params: EmptyParamsDto,
  ) {
    return this.account.deleteHealthData(user);
  }
}
