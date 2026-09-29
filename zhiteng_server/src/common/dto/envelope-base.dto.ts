import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID } from 'class-validator';

/** Every envelope params object must include user_id (may be empty before login). */
export class EnvelopeUserIdDto {
  @ApiProperty({
    description: '客户端上报的用户 ID；登录前传空字符串。服务端不信任此字段做鉴权。',
    example: '',
  })
  @IsString()
  user_id!: string;
}

export class IdParamsDto extends EnvelopeUserIdDto {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  id!: string;
}

export class EmptyParamsDto extends EnvelopeUserIdDto {}

export class OptionalIfMatchDto {
  @ApiPropertyOptional({
    description: '乐观锁 revision，对应原 If-Match 头',
  })
  @IsOptional()
  @IsString()
  ifMatch?: string;
}
