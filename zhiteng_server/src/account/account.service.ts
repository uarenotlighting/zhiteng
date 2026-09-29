import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { AuthUser } from '../common/auth.decorators';

@Injectable()
export class AccountService {
  constructor(private readonly prisma: PrismaService) {}

  async getMe(user: AuthUser) {
    const found = await this.prisma.user.findUnique({
      where: { id: user.userId },
      include: {
        identities: true,
        subjectsOwned: {
          where: { id: user.subjectId },
        },
      },
    });
    if (!found) {
      throw new NotFoundException('User not found');
    }
    return {
      id: found.id,
      status: found.status,
      subjectId: user.subjectId,
      identities: found.identities.map((i) => ({
        platform: i.platform,
        platformUserId: i.platformUserId,
        boundAt: i.boundAt,
      })),
      createdAt: found.createdAt,
    };
  }

  async deleteHealthData(user: AuthUser) {
    await this.prisma.$transaction(async (tx) => {
      const entries = await tx.painEntry.findMany({
        where: { subject: { ownerId: user.userId } },
        select: { id: true, revision: true },
      });

      for (const entry of entries) {
        await tx.syncTombstone.upsert({
          where: {
            entityType_entityId: {
              entityType: 'pain_entry',
              entityId: entry.id,
            },
          },
          create: {
            userId: user.userId,
            entityType: 'pain_entry',
            entityId: entry.id,
            revision: entry.revision + 1n,
          },
          update: {
            revision: entry.revision + 1n,
            deletedAt: new Date(),
          },
        });
      }

      await tx.painEntry.deleteMany({
        where: { subject: { ownerId: user.userId } },
      });
      await tx.focusArea.deleteMany({ where: { userId: user.userId } });
      await tx.scheduledReminder.deleteMany({ where: { userId: user.userId } });
      await tx.auditEvent.create({
        data: {
          userId: user.userId,
          action: 'account.health_data_deleted',
          meta: { entryCount: entries.length },
        },
      });
    });

    return { ok: true };
  }
}
