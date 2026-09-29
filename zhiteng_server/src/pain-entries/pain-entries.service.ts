import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  PainEntryStatus,
  Prisma,
  TimelineEventType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import type { AuthUser } from '../common/auth.decorators';
import {
  decodeSensitive,
  encodeSensitive,
} from '../common/crypto.util';
import { CreatePainEntryDto } from './dto/create-pain-entry.dto';
import { UpdatePainEntryDto } from './dto/update-pain-entry.dto';
import { AddTimelineEventDto } from './dto/add-timeline-event.dto';
import { ListPainEntriesQueryDto } from './dto/list-pain-entries.query';

const entryInclude = {
  locations: true,
  timeline: { orderBy: { occurredAt: 'asc' as const } },
  intensityObservations: { orderBy: { observedAt: 'asc' as const } },
  medications: true,
  reliefActions: true,
} satisfies Prisma.PainEntryInclude;

@Injectable()
export class PainEntriesService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AuthUser, dto: CreatePainEntryDto) {
    if (dto.clientMutationId) {
      const existing = await this.prisma.painEntry.findUnique({
        where: { clientMutationId: dto.clientMutationId },
        include: entryInclude,
      });
      if (existing) {
        return this.serialize(existing);
      }
    }

    const startedAt = new Date(dto.startedAt);
    const created = await this.prisma.$transaction(async (tx) => {
      const entry = await tx.painEntry.create({
        data: {
          subjectId: user.subjectId,
          createdByUserId: user.userId,
          sourcePlatform: dto.sourcePlatform,
          startedAt,
          timezone: dto.timezone,
          utcOffsetMinutes: dto.utcOffsetMinutes,
          suspectedTriggers: dto.suspectedTriggers ?? [],
          accompanyingSymptoms: dto.accompanyingSymptoms ?? [],
          notesCiphertext: encodeSensitive(dto.notes),
          clientMutationId: dto.clientMutationId,
          bodyModelVersion: dto.bodyModelVersion,
          coordinateSystemVersion: dto.coordinateSystemVersion,
          taxonomyVersion: dto.taxonomyVersion,
          locations: dto.locations?.length
            ? {
                create: dto.locations.map((loc) => ({
                  bodyPartId: loc.bodyPartId,
                  side: loc.side,
                  view: loc.view,
                  layer: loc.layer,
                  geometryType: loc.geometryType,
                  normalizedX: loc.normalizedX,
                  normalizedY: loc.normalizedY,
                  radius: loc.radius,
                  intensity0to10: loc.intensity0to10,
                  intensityLabel: loc.intensityLabel,
                  sensations: loc.sensations ?? [],
                  certainty: loc.certainty,
                })),
              }
            : undefined,
          timeline: {
            create: {
              occurredAt: startedAt,
              type: TimelineEventType.start,
              payload: {
                initialIntensity0to10: dto.initialIntensity0to10 ?? null,
              },
            },
          },
          intensityObservations:
            dto.initialIntensity0to10 != null
              ? {
                  create: {
                    observedAt: startedAt,
                    intensity0to10: dto.initialIntensity0to10,
                  },
                }
              : undefined,
        },
        include: entryInclude,
      });
      return entry;
    });

    return this.serialize(created);
  }

  async list(user: AuthUser, query: ListPainEntriesQueryDto) {
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const where: Prisma.PainEntryWhereInput = {
      subjectId: user.subjectId,
      deletedAt: null,
      ...(query.status ? { status: query.status } : {}),
    };

    const [total, items] = await this.prisma.$transaction([
      this.prisma.painEntry.count({ where }),
      this.prisma.painEntry.findMany({
        where,
        include: entryInclude,
        orderBy: { startedAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
    ]);

    return {
      page,
      pageSize,
      total,
      items: items.map((item) => this.serialize(item)),
    };
  }

  async getOne(user: AuthUser, id: string) {
    const entry = await this.findOwned(user, id);
    return this.serialize(entry);
  }

  async update(
    user: AuthUser,
    id: string,
    dto: {
      status?: UpdatePainEntryDto['status'];
      endedAt?: string;
      suspectedTriggers?: string[];
      accompanyingSymptoms?: string[];
      notes?: string;
    },
    ifMatch?: string,
  ) {
    const entry = await this.findOwned(user, id);
    this.assertRevision(entry.revision, ifMatch);

    const updated = await this.prisma.painEntry.update({
      where: { id: entry.id },
      data: {
        status: dto.status,
        endedAt: dto.endedAt ? new Date(dto.endedAt) : undefined,
        suspectedTriggers: dto.suspectedTriggers,
        accompanyingSymptoms: dto.accompanyingSymptoms,
        notesCiphertext:
          dto.notes !== undefined ? encodeSensitive(dto.notes) : undefined,
        revision: { increment: 1 },
      },
      include: entryInclude,
    });

    return this.serialize(updated);
  }

  async addTimelineEvent(
    user: AuthUser,
    id: string,
    dto: {
      occurredAt: string;
      type: AddTimelineEventDto['type'];
      payload?: Record<string, unknown>;
      intensity0to10?: number;
      clientMutationId?: string;
    },
  ) {
    await this.findOwned(user, id);

    if (dto.clientMutationId) {
      const existing = await this.prisma.timelineEvent.findUnique({
        where: { clientMutationId: dto.clientMutationId },
      });
      if (existing) {
        const entry = await this.findOwned(user, id);
        return this.serialize(entry);
      }
    }

    const occurredAt = new Date(dto.occurredAt);
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.timelineEvent.create({
        data: {
          painEntryId: id,
          occurredAt,
          type: dto.type,
          payload: (dto.payload ?? {}) as Prisma.InputJsonValue,
          clientMutationId: dto.clientMutationId,
        },
      });

      if (
        dto.type === TimelineEventType.intensity_change &&
        dto.intensity0to10 != null
      ) {
        await tx.intensityObservation.create({
          data: {
            painEntryId: id,
            observedAt: occurredAt,
            intensity0to10: dto.intensity0to10,
            clientMutationId: dto.clientMutationId,
          },
        });
      }

      if (dto.type === TimelineEventType.end) {
        await tx.painEntry.update({
          where: { id },
          data: {
            status: PainEntryStatus.completed,
            endedAt: occurredAt,
            revision: { increment: 1 },
          },
        });
      } else {
        await tx.painEntry.update({
          where: { id },
          data: { revision: { increment: 1 } },
        });
      }

      return tx.painEntry.findUniqueOrThrow({
        where: { id },
        include: entryInclude,
      });
    });

    return this.serialize(updated);
  }

  async complete(user: AuthUser, id: string) {
    const entry = await this.findOwned(user, id);
    const endedAt = new Date();

    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.timelineEvent.create({
        data: {
          painEntryId: id,
          occurredAt: endedAt,
          type: TimelineEventType.end,
          payload: {},
        },
      });
      return tx.painEntry.update({
        where: { id: entry.id },
        data: {
          status: PainEntryStatus.completed,
          endedAt,
          revision: { increment: 1 },
        },
        include: entryInclude,
      });
    });

    return this.serialize(updated);
  }

  private async findOwned(user: AuthUser, id: string) {
    const entry = await this.prisma.painEntry.findFirst({
      where: {
        id,
        subjectId: user.subjectId,
        deletedAt: null,
      },
      include: entryInclude,
    });
    if (!entry) {
      throw new NotFoundException('Pain entry not found');
    }
    return entry;
  }

  private assertRevision(current: bigint, ifMatch?: string) {
    if (!ifMatch) return;
    const expected = ifMatch.replace(/"/g, '').trim();
    if (expected !== String(current)) {
      throw new ConflictException({
        message: 'Revision conflict',
        currentRevision: String(current),
      });
    }
  }

  private serialize(
    entry: Prisma.PainEntryGetPayload<{ include: typeof entryInclude }>,
  ) {
    return {
      id: entry.id,
      subjectId: entry.subjectId,
      createdByUserId: entry.createdByUserId,
      sourcePlatform: entry.sourcePlatform,
      status: entry.status,
      startedAt: entry.startedAt,
      endedAt: entry.endedAt,
      timezone: entry.timezone,
      utcOffsetMinutes: entry.utcOffsetMinutes,
      suspectedTriggers: entry.suspectedTriggers,
      accompanyingSymptoms: entry.accompanyingSymptoms,
      notes: decodeSensitive(entry.notesCiphertext),
      completionState: entry.completionState,
      bodyModelVersion: entry.bodyModelVersion,
      coordinateSystemVersion: entry.coordinateSystemVersion,
      taxonomyVersion: entry.taxonomyVersion,
      revision: String(entry.revision),
      clientMutationId: entry.clientMutationId,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      locations: entry.locations,
      timelineEvents: entry.timeline,
      intensityObservations: entry.intensityObservations,
      medications: entry.medications.map((m) => ({
        ...m,
        name: decodeSensitive(m.nameCiphertext),
        notes: decodeSensitive(m.notesCiphertext),
        nameCiphertext: undefined,
        notesCiphertext: undefined,
      })),
      reliefActions: entry.reliefActions.map((r) => ({
        ...r,
        notes: decodeSensitive(r.notesCiphertext),
        notesCiphertext: undefined,
      })),
    };
  }
}
