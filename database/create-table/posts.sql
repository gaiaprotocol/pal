CREATE TABLE IF NOT EXISTS "public"."posts" (
    "id" bigint NOT NULL,
    "target" smallint,
    "chain" "text",
    "token_address" "text",
    "author" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "message" "text" NOT NULL,
    "translated" "jsonb",
    "rich" "jsonb",
    "parent" bigint,
    "comment_count" integer DEFAULT 0 NOT NULL,
    "repost_count" integer DEFAULT 0 NOT NULL,
    "like_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);

ALTER TABLE "public"."posts" OWNER TO "postgres";
ALTER TABLE "public"."posts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."posts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_author_fkey" FOREIGN KEY ("author") REFERENCES "public"."users_public"("user_id");

ALTER TABLE "public"."posts" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "view everyone or only token holders" ON "public"."posts" FOR SELECT USING ((("target" = 0) OR ("author" = "auth"."uid"()) OR ("chain" IS NULL) OR ("token_address" IS NULL) OR ((( SELECT "tokens"."owner"
   FROM "public"."tokens"
  WHERE (("tokens"."chain" = "posts"."chain") AND ("tokens"."token_address" = "posts"."token_address"))) = ( SELECT "users_public"."wallet_address"
   FROM "public"."users_public"
  WHERE ("users_public"."user_id" = "auth"."uid"()))) OR (( SELECT "tokens"."view_token_required"
   FROM "public"."tokens"
  WHERE (("tokens"."chain" = "posts"."chain") AND ("tokens"."token_address" = "posts"."token_address"))) <= ( SELECT "token_holders"."last_fetched_balance"
   FROM "public"."token_holders"
  WHERE (("token_holders"."chain" = "posts"."chain") AND ("token_holders"."token_address" = "posts"."token_address") AND ("token_holders"."wallet_address" = ( SELECT "users_public"."wallet_address"
           FROM "public"."users_public"
          WHERE ("users_public"."user_id" = "auth"."uid"())))))))));

CREATE POLICY "can write only authed" ON "public"."posts" FOR INSERT TO "authenticated" WITH CHECK ((("message" <> ''::"text") AND ("length"("message") <= 2000) AND ("author" = "auth"."uid"()) and ((SELECT blocked from users_public where user_id = auth.uid()) <> true) AND ((( SELECT "tokens"."owner"
   FROM "public"."tokens"
  WHERE (("tokens"."chain" = "posts"."chain") AND ("tokens"."token_address" = "posts"."token_address"))) = ( SELECT "users_public"."wallet_address"
   FROM "public"."users_public"
  WHERE ("users_public"."user_id" = "auth"."uid"()))) OR (( SELECT "tokens"."write_token_required"
   FROM "public"."tokens"
  WHERE (("tokens"."chain" = "posts"."chain") AND ("tokens"."token_address" = "posts"."token_address"))) <= ( SELECT "token_holders"."last_fetched_balance"
   FROM "public"."token_holders"
  WHERE (("token_holders"."chain" = "posts"."chain") AND ("token_holders"."token_address" = "posts"."token_address") AND ("token_holders"."wallet_address" = ( SELECT "users_public"."wallet_address"
           FROM "public"."users_public"
          WHERE ("users_public"."user_id" = "auth"."uid"())))))))));

CREATE POLICY "can delete only authed" ON "public"."posts" FOR DELETE TO "authenticated" USING (("author" = "auth"."uid"()));

GRANT ALL ON TABLE "public"."posts" TO "anon";
GRANT ALL ON TABLE "public"."posts" TO "authenticated";
GRANT ALL ON TABLE "public"."posts" TO "service_role";

GRANT ALL ON SEQUENCE "public"."posts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posts_id_seq" TO "service_role";
