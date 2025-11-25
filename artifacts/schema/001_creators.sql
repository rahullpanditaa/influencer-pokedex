-- this table will hold the output of the llm enrichment step

CREATE TABLE "creators" (
    "id" UUID,
    "name" TEXT NOT NULL,
    "primary_niche" TEXT NOT NULL,
    "secondary_niches" TEXT[] NOT NULL,
    "style" TEXT NOT NULL,
    "summary" TEXT NOT NULL,
    PRIMARY KEY("id")
);