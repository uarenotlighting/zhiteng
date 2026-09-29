import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { PainEntryStatus } from '@prisma/client';
import {
  IsArray,
  IsEnum,
  IsOptional,
  IsString,
  IsUUID,
} from 'class-validator';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class UpdatePainEntryDto extends EnvelopeUserIdDto {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  id!: string;

  @ApiPropertyOptional({
    description: '乐观锁 revision，对应原 If-Match 头',
  })
  @IsOptional()
  @IsString()
  ifMatch?: string;

  @ApiPropertyOptional({ enum: PainEntryStatus })
  @IsOptional()
  @IsEnum(PainEntryStatus)
  status?: PainEntryStatus;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  endedAt?: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  suspectedTriggers?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  accompanyingSymptoms?: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}
