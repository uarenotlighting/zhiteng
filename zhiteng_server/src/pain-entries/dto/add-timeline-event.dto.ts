import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TimelineEventType } from '@prisma/client';
import {
  IsEnum,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from 'class-validator';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class AddTimelineEventDto extends EnvelopeUserIdDto {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  id!: string;

  @ApiProperty({ example: '2026-09-21T12:30:00.000Z' })
  @IsString()
  occurredAt!: string;

  @ApiProperty({ enum: TimelineEventType })
  @IsEnum(TimelineEventType)
  type!: TimelineEventType;

  @ApiPropertyOptional({ type: Object })
  @IsOptional()
  @IsObject()
  payload?: Record<string, unknown>;

  @ApiPropertyOptional({
    description: '强度变化时建议同时写入，便于稳定统计',
    minimum: 0,
    maximum: 10,
  })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(10)
  intensity0to10?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  clientMutationId?: string;
}
