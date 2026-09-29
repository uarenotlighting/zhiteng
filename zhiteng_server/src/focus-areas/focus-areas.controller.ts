import { Controller, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/auth.decorators';
import type { AuthUser } from '../common/auth.decorators';
import { EmptyParamsDto } from '../common/dto/envelope-base.dto';
import { RequestParams } from '../common/request-envelope';
import { FocusAreasService } from './focus-areas.service';
import { CreateFocusAreaDto } from './dto/create-focus-area.dto';

@ApiTags('focus-areas')
@ApiBearerAuth()
@Controller({ path: 'focus-areas', version: '1' })
export class FocusAreasController {
  constructor(private readonly focusAreas: FocusAreasService) {}

  @Post('list')
  @ApiOperation({ summary: '列出关注区域' })
  list(
    @CurrentUser() user: AuthUser,
    @RequestParams() _params: EmptyParamsDto,
  ) {
    return this.focusAreas.list(user);
  }

  @Post('create')
  @ApiOperation({ summary: '创建关注区域' })
  create(
    @CurrentUser() user: AuthUser,
    @RequestParams() dto: CreateFocusAreaDto,
  ) {
    return this.focusAreas.create(user, dto);
  }
}
