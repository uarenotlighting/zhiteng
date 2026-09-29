import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppConfigModule } from './config/app-config.module';
import { PrismaModule } from './prisma/prisma.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { PainEntriesModule } from './pain-entries/pain-entries.module';
import { FocusAreasModule } from './focus-areas/focus-areas.module';
import { SyncModule } from './sync/sync.module';
import { AccountModule } from './account/account.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, envFilePath: ['.env'] }),
    AppConfigModule,
    PrismaModule,
    HealthModule,
    AuthModule,
    AccountModule,
    PainEntriesModule,
    FocusAreasModule,
    SyncModule,
  ],
})
export class AppModule {}
