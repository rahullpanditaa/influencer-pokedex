CREATE TABLE "creator_accounts" (
    "id" UUID,
    "creator_id" UUID,
    "platform" TEXT NOT NULL CHECK ("platform" IN ('instagram', 'youtube')),
    "username" TEXT NOT NULL,
    "followers" INTEGER NOT NULL CHECK ("followers" >= 0),
    "bio" TEXT NOT NULL,
    UNIQUE ("platform", "username"),
    PRIMARY KEY("id"),
    FOREIGN KEY("creator_id") REFERENCES "creators"("id") ON DELETE CASCADE
);