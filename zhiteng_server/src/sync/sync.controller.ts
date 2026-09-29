import { Controller, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/auth.decorators';
import type { AuthUser } from '../common/auth.decorators';
import { RequestParams } from '../common/request-envelope';
import { SyncService } from './sync.service';
import { SyncChangesQueryDto } from './dto/sync-changes.query';

@ApiTags('sync')
@ApiBearerAuth()
@Controller({ path: 'sync', version: '1' })
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post('changes')
  @ApiOperation({
    summary: '增量拉取变更（App/Watch 复用）',
    description: 'cursor 为上次返回的 nextCursor；首次可不传。',
  })
  changes(
    @CurrentUser() user: AuthUser,
    @RequestParams() query: SyncChangesQueryDto,
  ) {
    return this.sync.getChanges(user, query);
  }
}
