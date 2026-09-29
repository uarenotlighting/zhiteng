import { ApiPropertyOptional } from '@nestjs/swagger';
import { PainEntryStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class ListPainEntriesQueryDto extends EnvelopeUserIdDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize?: number = 20;

  @ApiPropertyOptional({ enum: PainEntryStatus })
  @IsOptional()
  @IsEnum(PainEntryStatus)
  status?: PainEntryStatus;
}
