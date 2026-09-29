import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { BodySide, BodyView, FocusAreaCreatedBy } from '@prisma/client';
import {
  IsArray,
  IsEnum,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Min,
} from 'class-validator';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class CreateFocusAreaDto extends EnvelopeUserIdDto {
  @ApiProperty({ example: '右膝' })
  @IsString()
  name!: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  regionIds?: string[];

  @ApiPropertyOptional({ enum: BodySide })
  @IsOptional()
  @IsEnum(BodySide)
  preferredSide?: BodySide;

  @ApiPropertyOptional({ enum: BodyView })
  @IsOptional()
  @IsEnum(BodyView)
  preferredView?: BodyView;

  @ApiPropertyOptional({ type: Object })
  @IsOptional()
  @IsObject()
  zoomRect?: Record<string, unknown>;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @ApiPropertyOptional({ enum: FocusAreaCreatedBy })
  @IsOptional()
  @IsEnum(FocusAreaCreatedBy)
  createdBy?: FocusAreaCreatedBy;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  clientMutationId?: string;
}
