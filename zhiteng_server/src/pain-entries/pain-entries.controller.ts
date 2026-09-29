import { Controller, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/auth.decorators';
import type { AuthUser } from '../common/auth.decorators';
import { IdParamsDto } from '../common/dto/envelope-base.dto';
import { RequestParams } from '../common/request-envelope';
import { PainEntriesService } from './pain-entries.service';
import { CreatePainEntryDto } from './dto/create-pain-entry.dto';
import { UpdatePainEntryDto } from './dto/update-pain-entry.dto';
import { AddTimelineEventDto } from './dto/add-timeline-event.dto';
import { ListPainEntriesQueryDto } from './dto/list-pain-entries.query';

@ApiTags('pain-entries')
@ApiBearerAuth()
@Controller({ path: 'pain-entries', version: '1' })
export class PainEntriesController {
  constructor(private readonly painEntries: PainEntriesService) {}

  @Post('create')
  @ApiOperation({ summary: '创建疼痛记录' })
  create(
    @CurrentUser() user: AuthUser,
    @RequestParams() dto: CreatePainEntryDto,
  ) {
    return this.painEntries.create(user, dto);
  }

  @Post('list')
  @ApiOperation({ summary: '分页列出疼痛记录' })
  list(
    @CurrentUser() user: AuthUser,
    @RequestParams() query: ListPainEntriesQueryDto,
  ) {
    return this.painEntries.list(user, query);
  }

  @Post('detail')
  @ApiOperation({ summary: '获取单条疼痛记录详情' })
  getOne(
    @CurrentUser() user: AuthUser,
    @RequestParams() dto: IdParamsDto,
  ) {
    return this.painEntries.getOne(user, dto.id);
  }

  @Post('update')
  @ApiOperation({ summary: '更新疼痛记录（乐观锁 ifMatch/revision）' })
  update(
    @CurrentUser() user: AuthUser,
    @RequestParams() dto: UpdatePainEntryDto,
  ) {
    const { id, ifMatch, ...patch } = dto;
    return this.painEntries.update(user, id, patch, ifMatch);
  }

  @Post('timeline-events/create')
  @ApiOperation({ summary: '追加时间线事件（幂等 clientMutationId）' })
  addTimelineEvent(
    @CurrentUser() user: AuthUser,
    @RequestParams() dto: AddTimelineEventDto,
  ) {
    const { id, ...event } = dto;
    return this.painEntries.addTimelineEvent(user, id, event);
  }

  @Post('complete')
  @ApiOperation({ summary: '结束一次疼痛发作' })
  complete(
    @CurrentUser() user: AuthUser,
    @RequestParams() dto: IdParamsDto,
  ) {
    return this.painEntries.complete(user, dto.id);
  }
}
