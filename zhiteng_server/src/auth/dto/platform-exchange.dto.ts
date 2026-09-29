import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Platform } from '@prisma/client';
import {
  IsEnum,
  IsOptional,
  IsString,
  MinLength,
  ValidateIf,
} from 'class-validator';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class PlatformExchangeDto extends EnvelopeUserIdDto {
  @ApiProperty({ enum: Platform, example: Platform.dev })
  @IsEnum(Platform)
  platform!: Platform;

  @ApiPropertyOptional({
    description: '微信/抖音等平台登录 code；正式平台登录必填',
  })
  @ValidateIf((o: PlatformExchangeDto) => o.platform !== Platform.dev)
  @IsString()
  @MinLength(1)
  code?: string;

  @ApiPropertyOptional({
    description: '仅开发模式：本地模拟平台用户 ID',
    example: 'local-dev-user-1',
  })
  @ValidateIf((o: PlatformExchangeDto) => o.platform === Platform.dev)
  @IsString()
  @MinLength(1)
  devUserId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  deviceLabel?: string;

  @ApiPropertyOptional({ example: 'Asia/Shanghai' })
  @IsOptional()
  @IsString()
  timezone?: string;
}
