import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { AuthUser } from '../common/auth.decorators';
import { SyncChangesQueryDto } from './dto/sync-changes.query';

@Injectable()
export class SyncService {
  constructor(private readonly prisma: PrismaService) {}

  async getChanges(user: AuthUser, query: SyncChangesQueryDto) {
    const limit = query.limit ?? 100;
    const since = query.cursor ? new Date(query.cursor) : new Date(0);

    const [entries, focusAreas, tombstones] = await Promise.all([
      this.prisma.painEntry.findMany({
        where: {
          subjectId: user.subjectId,
          updatedAt: { gt: since },
        },
        orderBy: { updatedAt: 'asc' },
        take: limit,
        select: {
          id: true,
          revision: true,
          updatedAt: true,
          deletedAt: true,
          status: true,
          startedAt: true,
          endedAt: true,
        },
      }),
      this.prisma.focusArea.findMany({
        where: {
          userId: user.userId,
          updatedAt: { gt: since },
        },
        orderBy: { updatedAt: 'asc' },
        take: limit,
        select: {
          id: true,
          revision: true,
          updatedAt: true,
          deletedAt: true,
          name: true,
          sortOrder: true,
        },
      }),
      this.prisma.syncTombstone.findMany({
        where: {
          userId: user.userId,
          deletedAt: { gt: since },
        },
        orderBy: { deletedAt: 'asc' },
        take: limit,
      }),
    ]);

    const timestamps = [
      ...entries.map((e) => e.updatedAt.getTime()),
      ...focusAreas.map((f) => f.updatedAt.getTime()),
      ...tombstones.map((t) => t.deletedAt.getTime()),
    ];

    const nextCursor =
      timestamps.length > 0
        ? new Date(Math.max(...timestamps)).toISOString()
        : query.cursor ?? null;

    return {
      nextCursor,
      changes: {
        painEntries: entries.map((e) => ({
          ...e,
          revision: String(e.revision),
        })),
        focusAreas: focusAreas.map((f) => ({
          ...f,
          revision: String(f.revision),
        })),
        tombstones: tombstones.map((t) => ({
          ...t,
          revision: String(t.revision),
        })),
      },
    };
  }
}
