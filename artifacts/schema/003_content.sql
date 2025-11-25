CREATE TABLE "content_items" (
    "id" UUID,
    "creator_account_id" UUID,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "published_at" TIMESTAMP,
    PRIMARY KEY("id"),
    FOREIGN KEY("creator_account_id") REFERENCES "creator_accounts"("id") ON DELETE CASCADE
);