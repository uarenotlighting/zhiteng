import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import type { AuthUser } from '../common/auth.decorators';
import { CreateFocusAreaDto } from './dto/create-focus-area.dto';

@Injectable()
export class FocusAreasService {
  constructor(private readonly prisma: PrismaService) {}

  async list(user: AuthUser) {
    const items = await this.prisma.focusArea.findMany({
      where: { userId: user.userId, deletedAt: null },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });
    return items.map((item) => ({
      ...item,
      revision: String(item.revision),
    }));
  }

  async create(user: AuthUser, dto: CreateFocusAreaDto) {
    if (dto.clientMutationId) {
      const existing = await this.prisma.focusArea.findUnique({
        where: { clientMutationId: dto.clientMutationId },
      });
      if (existing) {
        return { ...existing, revision: String(existing.revision) };
      }
    }

    const created = await this.prisma.focusArea.create({
      data: {
        userId: user.userId,
        name: dto.name,
        regionIds: dto.regionIds ?? [],
        preferredSide: dto.preferredSide,
        preferredView: dto.preferredView,
        zoomRect: (dto.zoomRect ?? Prisma.JsonNull) as Prisma.InputJsonValue,
        sortOrder: dto.sortOrder ?? 0,
        createdBy: dto.createdBy,
        clientMutationId: dto.clientMutationId,
      },
    });

    return { ...created, revision: String(created.revision) };
  }
}
