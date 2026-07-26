CREATE TABLE "notes" (
	"id" serial PRIMARY KEY NOT NULL,
	"titre" text NOT NULL,
	"url" text,
	"contenu" text,
	"auteur" text NOT NULL,
	"cree_le" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "notes_cree_le_idx" ON "notes" USING btree ("cree_le");