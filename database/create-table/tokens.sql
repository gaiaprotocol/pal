CREATE TABLE IF NOT EXISTS "public"."tokens" (
    "chain" "text" NOT NULL,
    "token_address" "text" NOT NULL,
    "owner" "text" NOT NULL,
    "name" "text" NOT NULL,
    "symbol" "text" NOT NULL,
    "image" "text",
    "metadata" "jsonb",
    "supply" numeric DEFAULT '0'::numeric NOT NULL,
    "last_fetched_key_price" numeric DEFAULT '68750000000000'::numeric NOT NULL,
    "total_trading_key_volume" numeric DEFAULT '0'::numeric NOT NULL,
    "is_price_up" boolean,
    "last_message" "text",
    "last_message_sent_at" timestamp with time zone DEFAULT '-infinity'::timestamp with time zone NOT NULL,
    "holder_count" integer DEFAULT 1 NOT NULL,
    "last_key_purchased_at" timestamp with time zone DEFAULT '-infinity'::timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);

ALTER TABLE "public"."tokens" OWNER TO "postgres";

ALTER TABLE ONLY "public"."tokens"
    ADD CONSTRAINT "tokens_pkey" PRIMARY KEY ("chain", "token_address");

ALTER TABLE "public"."tokens" ENABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE "public"."tokens" TO "anon";
GRANT ALL ON TABLE "public"."tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."tokens" TO "service_role";
