import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';
import { EnvelopeUserIdDto } from '../../common/dto/envelope-base.dto';

export class RefreshTokenDto extends EnvelopeUserIdDto {
  @ApiProperty()
  @IsString()
  @MinLength(10)
  refreshToken!: string;
}
