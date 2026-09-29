import { Module } from '@nestjs/common';
import { PainEntriesController } from './pain-entries.controller';
import { PainEntriesService } from './pain-entries.service';

@Module({
  controllers: [PainEntriesController],
  providers: [PainEntriesService],
  exports: [PainEntriesService],
})
export class PainEntriesModule {}
