import { Module } from '@nestjs/common';
import { FocusAreasController } from './focus-areas.controller';
import { FocusAreasService } from './focus-areas.service';

@Module({
  controllers: [FocusAreasController],
  providers: [FocusAreasService],
})
export class FocusAreasModule {}
