-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('active', 'disabled', 'deleted');

-- CreateEnum
CREATE TYPE "Platform" AS ENUM ('weixin', 'douyin', 'xiaohongshu', 'apple', 'phone', 'passkey', 'dev');

-- CreateEnum
CREATE TYPE "SubjectKind" AS ENUM ('self', 'other');

-- CreateEnum
CREATE TYPE "MembershipRole" AS ENUM ('owner', 'caregiver', 'viewer');

-- CreateEnum
CREATE TYPE "PainEntryStatus" AS ENUM ('ongoing', 'completed');

-- CreateEnum
CREATE TYPE "BodySide" AS ENUM ('left', 'right', 'center', 'bilateral', 'unknown');

-- CreateEnum
CREATE TYPE "BodyView" AS ENUM ('front', 'back', 'side');

-- CreateEnum
CREATE TYPE "BodyLayer" AS ENUM ('surface', 'deep', 'muscle', 'bone', 'organ', 'unknown');

-- CreateEnum
CREATE TYPE "GeometryType" AS ENUM ('point', 'area');

-- CreateEnum
CREATE TYPE "Certainty" AS ENUM ('exact', 'approximate', 'unknown');

-- CreateEnum
CREATE TYPE "TimelineEventType" AS ENUM ('start', 'intensity_change', 'location_change', 'medication', 'relief', 'end', 'note');

-- CreateEnum
CREATE TYPE "MedicationEffectResult" AS ENUM ('recovered', 'relieved', 'no_effect');

-- CreateEnum
CREATE TYPE "FocusAreaCreatedBy" AS ENUM ('user', 'suggested');

-- CreateEnum
CREATE TYPE "ReminderKind" AS ENUM ('medication_followup', 'stale_entry', 'custom');

-- CreateEnum
CREATE TYPE "ReminderStatus" AS ENUM ('pending', 'sent', 'cancelled', 'failed');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "status" "UserStatus" NOT NULL DEFAULT 'active',
    "merged_into_user_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_identities" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "platform" "Platform" NOT NULL,
    "platform_user_id" TEXT NOT NULL,
    "platform_union_id" TEXT,
    "bound_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "platform_identities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "revoked_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subjects" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "kind" "SubjectKind" NOT NULL DEFAULT 'self',
    "display_name" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "subjects_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subject_memberships" (
    "id" UUID NOT NULL,
    "subject_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "MembershipRole" NOT NULL DEFAULT 'owner',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subject_memberships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "privacy_consents" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "policy_version" TEXT NOT NULL,
    "purpose" TEXT NOT NULL,
    "consented_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source_platform" "Platform" NOT NULL,

    CONSTRAINT "privacy_consents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "platform" "Platform" NOT NULL,
    "device_label" TEXT,
    "push_token" TEXT,
    "timezone" TEXT,
    "last_seen_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pain_entries" (
    "id" UUID NOT NULL,
    "subject_id" UUID NOT NULL,
    "created_by_user_id" UUID NOT NULL,
    "source_platform" "Platform" NOT NULL,
    "status" "PainEntryStatus" NOT NULL DEFAULT 'ongoing',
    "started_at" TIMESTAMPTZ(3) NOT NULL,
    "ended_at" TIMESTAMPTZ(3),
    "timezone" TEXT,
    "utc_offset_minutes" INTEGER,
    "suspected_triggers" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "accompanying_symptoms" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "notes_ciphertext" TEXT,
    "completion_state" JSONB,
    "body_model_version" TEXT,
    "coordinate_system_version" TEXT,
    "taxonomy_version" TEXT,
    "revision" BIGINT NOT NULL DEFAULT 1,
    "client_mutation_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "pain_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pain_locations" (
    "id" UUID NOT NULL,
    "pain_entry_id" UUID NOT NULL,
    "body_part_id" TEXT,
    "side" "BodySide" NOT NULL DEFAULT 'unknown',
    "view" "BodyView" NOT NULL DEFAULT 'front',
    "layer" "BodyLayer" NOT NULL DEFAULT 'unknown',
    "geometry_type" "GeometryType" NOT NULL DEFAULT 'point',
    "normalized_x" DOUBLE PRECISION,
    "normalized_y" DOUBLE PRECISION,
    "radius" DOUBLE PRECISION,
    "polygon" JSONB,
    "mask_object_key" TEXT,
    "intensity_0_to_10" INTEGER,
    "intensity_label" TEXT,
    "sensations" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "certainty" "Certainty" NOT NULL DEFAULT 'unknown',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "pain_locations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "location_relations" (
    "id" UUID NOT NULL,
    "from_location_id" UUID NOT NULL,
    "to_location_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "noted_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "location_relations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "intensity_observations" (
    "id" UUID NOT NULL,
    "pain_entry_id" UUID NOT NULL,
    "observed_at" TIMESTAMPTZ(3) NOT NULL,
    "intensity_0_to_10" INTEGER NOT NULL,
    "note" TEXT,
    "client_mutation_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "intensity_observations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "timeline_events" (
    "id" UUID NOT NULL,
    "pain_entry_id" UUID NOT NULL,
    "occurred_at" TIMESTAMPTZ(3) NOT NULL,
    "type" "TimelineEventType" NOT NULL,
    "schema_version" INTEGER NOT NULL DEFAULT 1,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "client_mutation_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "timeline_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "medications" (
    "id" UUID NOT NULL,
    "pain_entry_id" UUID NOT NULL,
    "name_ciphertext" TEXT NOT NULL,
    "dose" TEXT,
    "unit" TEXT,
    "taken_at" TIMESTAMPTZ(3) NOT NULL,
    "effect_due_at" TIMESTAMPTZ(3),
    "effect_checked_at" TIMESTAMPTZ(3),
    "effect_result" "MedicationEffectResult",
    "notes_ciphertext" TEXT,
    "client_mutation_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "medications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "relief_actions" (
    "id" UUID NOT NULL,
    "pain_entry_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "started_at" TIMESTAMPTZ(3) NOT NULL,
    "effect_score" INTEGER,
    "notes_ciphertext" TEXT,
    "client_mutation_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "relief_actions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "focus_areas" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "region_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "preferred_side" "BodySide",
    "preferred_view" "BodyView",
    "zoom_rect" JSONB,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_by" "FocusAreaCreatedBy" NOT NULL DEFAULT 'user',
    "revision" BIGINT NOT NULL DEFAULT 1,
    "client_mutation_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "focus_areas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "scheduled_reminders" (
    "id" UUID NOT NULL,
    "pain_entry_id" UUID,
    "user_id" UUID NOT NULL,
    "kind" "ReminderKind" NOT NULL,
    "due_at" TIMESTAMPTZ(3) NOT NULL,
    "status" "ReminderStatus" NOT NULL DEFAULT 'pending',
    "payload" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "scheduled_reminders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sync_tombstones" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" UUID NOT NULL,
    "revision" BIGINT NOT NULL,
    "deleted_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sync_tombstones_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_events" (
    "id" UUID NOT NULL,
    "user_id" UUID,
    "action" TEXT NOT NULL,
    "meta" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "users_merged_into_user_id_idx" ON "users"("merged_into_user_id");

-- CreateIndex
CREATE INDEX "platform_identities_user_id_idx" ON "platform_identities"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "platform_identities_platform_platform_user_id_key" ON "platform_identities"("platform", "platform_user_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_token_hash_idx" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "subjects_owner_id_idx" ON "subjects"("owner_id");

-- CreateIndex
CREATE UNIQUE INDEX "subject_memberships_subject_id_user_id_key" ON "subject_memberships"("subject_id", "user_id");

-- CreateIndex
CREATE INDEX "privacy_consents_user_id_idx" ON "privacy_consents"("user_id");

-- CreateIndex
CREATE INDEX "devices_user_id_idx" ON "devices"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "pain_entries_client_mutation_id_key" ON "pain_entries"("client_mutation_id");

-- CreateIndex
CREATE INDEX "pain_entries_subject_id_started_at_idx" ON "pain_entries"("subject_id", "started_at" DESC);

-- CreateIndex
CREATE INDEX "pain_entries_created_by_user_id_idx" ON "pain_entries"("created_by_user_id");

-- CreateIndex
CREATE INDEX "pain_entries_updated_at_idx" ON "pain_entries"("updated_at");

-- CreateIndex
CREATE INDEX "pain_entries_deleted_at_idx" ON "pain_entries"("deleted_at");

-- CreateIndex
CREATE INDEX "pain_locations_pain_entry_id_idx" ON "pain_locations"("pain_entry_id");

-- CreateIndex
CREATE INDEX "location_relations_from_location_id_idx" ON "location_relations"("from_location_id");

-- CreateIndex
CREATE INDEX "location_relations_to_location_id_idx" ON "location_relations"("to_location_id");

-- CreateIndex
CREATE UNIQUE INDEX "intensity_observations_client_mutation_id_key" ON "intensity_observations"("client_mutation_id");

-- CreateIndex
CREATE INDEX "intensity_observations_pain_entry_id_observed_at_idx" ON "intensity_observations"("pain_entry_id", "observed_at");

-- CreateIndex
CREATE UNIQUE INDEX "timeline_events_client_mutation_id_key" ON "timeline_events"("client_mutation_id");

-- CreateIndex
CREATE INDEX "timeline_events_pain_entry_id_occurred_at_idx" ON "timeline_events"("pain_entry_id", "occurred_at");

-- CreateIndex
CREATE UNIQUE INDEX "medications_client_mutation_id_key" ON "medications"("client_mutation_id");

-- CreateIndex
CREATE INDEX "medications_pain_entry_id_taken_at_idx" ON "medications"("pain_entry_id", "taken_at");

-- CreateIndex
CREATE UNIQUE INDEX "relief_actions_client_mutation_id_key" ON "relief_actions"("client_mutation_id");

-- CreateIndex
CREATE INDEX "relief_actions_pain_entry_id_idx" ON "relief_actions"("pain_entry_id");

-- CreateIndex
CREATE UNIQUE INDEX "focus_areas_client_mutation_id_key" ON "focus_areas"("client_mutation_id");

-- CreateIndex
CREATE INDEX "focus_areas_user_id_sort_order_idx" ON "focus_areas"("user_id", "sort_order");

-- CreateIndex
CREATE INDEX "scheduled_reminders_status_due_at_idx" ON "scheduled_reminders"("status", "due_at");

-- CreateIndex
CREATE INDEX "scheduled_reminders_user_id_idx" ON "scheduled_reminders"("user_id");

-- CreateIndex
CREATE INDEX "sync_tombstones_user_id_deleted_at_idx" ON "sync_tombstones"("user_id", "deleted_at");

-- CreateIndex
CREATE UNIQUE INDEX "sync_tombstones_entity_type_entity_id_key" ON "sync_tombstones"("entity_type", "entity_id");

-- CreateIndex
CREATE INDEX "audit_events_user_id_created_at_idx" ON "audit_events"("user_id", "created_at");

-- AddForeignKey
ALTER TABLE "platform_identities" ADD CONSTRAINT "platform_identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subjects" ADD CONSTRAINT "subjects_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subject_memberships" ADD CONSTRAINT "subject_memberships_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "subjects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subject_memberships" ADD CONSTRAINT "subject_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "privacy_consents" ADD CONSTRAINT "privacy_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pain_entries" ADD CONSTRAINT "pain_entries_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "subjects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pain_entries" ADD CONSTRAINT "pain_entries_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pain_locations" ADD CONSTRAINT "pain_locations_pain_entry_id_fkey" FOREIGN KEY ("pain_entry_id") REFERENCES "pain_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "location_relations" ADD CONSTRAINT "location_relations_from_location_id_fkey" FOREIGN KEY ("from_location_id") REFERENCES "pain_locations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "location_relations" ADD CONSTRAINT "location_relations_to_location_id_fkey" FOREIGN KEY ("to_location_id") REFERENCES "pain_locations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "intensity_observations" ADD CONSTRAINT "intensity_observations_pain_entry_id_fkey" FOREIGN KEY ("pain_entry_id") REFERENCES "pain_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "timeline_events" ADD CONSTRAINT "timeline_events_pain_entry_id_fkey" FOREIGN KEY ("pain_entry_id") REFERENCES "pain_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "medications" ADD CONSTRAINT "medications_pain_entry_id_fkey" FOREIGN KEY ("pain_entry_id") REFERENCES "pain_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "relief_actions" ADD CONSTRAINT "relief_actions_pain_entry_id_fkey" FOREIGN KEY ("pain_entry_id") REFERENCES "pain_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "focus_areas" ADD CONSTRAINT "focus_areas_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "scheduled_reminders" ADD CONSTRAINT "scheduled_reminders_pain_entry_id_fkey" FOREIGN KEY ("pain_entry_id") REFERENCES "pain_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_events" ADD CONSTRAINT "audit_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
