import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Platform, BodySide, BodyView, BodyLayer, GeometryType, Certainty } from '@prisma/client';
import {
  IsArray,
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class CreatePainLocationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  bodyPartId?: string;

  @ApiPropertyOptional({ enum: BodySide })
  @IsOptional()
  @IsEnum(BodySide)
  side?: BodySide;

  @ApiPropertyOptional({ enum: BodyView })
  @IsOptional()
  @IsEnum(BodyView)
  view?: BodyView;

  @ApiPropertyOptional({ enum: BodyLayer })
  @IsOptional()
  @IsEnum(BodyLayer)
  layer?: BodyLayer;

  @ApiPropertyOptional({ enum: GeometryType })
  @IsOptional()
  @IsEnum(GeometryType)
  geometryType?: GeometryType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  normalizedX?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  normalizedY?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  radius?: number;

  @ApiPropertyOptional({ minimum: 0, maximum: 10 })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(10)
  intensity0to10?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  intensityLabel?: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  sensations?: string[];

  @ApiPropertyOptional({ enum: Certainty })
  @IsOptional()
  @IsEnum(Certainty)
  certainty?: Certainty;
}

export class CreatePainEntryDto extends EnvelopeUserIdDto {
  @ApiProperty({ enum: Platform, example: Platform.dev })
  @IsEnum(Platform)
  sourcePlatform!: Platform;

  @ApiProperty({ example: '2026-09-21T12:00:00.000Z' })
  @IsString()
  startedAt!: string;

  @ApiPropertyOptional({ example: 'Asia/Shanghai' })
  @IsOptional()
  @IsString()
  timezone?: string;

  @ApiPropertyOptional({ example: 480 })
  @IsOptional()
  @IsInt()
  utcOffsetMinutes?: number;

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

  @ApiPropertyOptional({ description: '自由文本备注（服务端加密存储）' })
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional({ type: [CreatePainLocationDto] })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreatePainLocationDto)
  locations?: CreatePainLocationDto[];

  @ApiPropertyOptional({
    description: '客户端幂等键，网络重试时传相同值可避免重复创建',
  })
  @IsOptional()
  @IsUUID()
  clientMutationId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  bodyModelVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  coordinateSystemVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  taxonomyVersion?: string;

  @ApiPropertyOptional({ minimum: 0, maximum: 10 })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(10)
  initialIntensity0to10?: number;
}
