
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

CREATE EXTENSION IF NOT EXISTS "http" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE OR REPLACE FUNCTION "public"."check_view_granted"("parameter_token_address" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$begin return auth.role() = 'authenticated'::text
and (
   (
      (
         SELECT pal_tokens.owner
         FROM pal_tokens
         WHERE (pal_tokens.token_address = parameter_token_address)
      ) = (
         SELECT user_details.wallet_address
         FROM user_details
         WHERE (user_details.id = auth.uid())
      )
   )
   or (
      (
         SELECT pal_tokens.view_token_required
         FROM pal_tokens
         WHERE (pal_tokens.token_address = parameter_token_address)
      ) <= (
         SELECT pal_token_balances.last_fetched_balance
         FROM pal_token_balances
         WHERE (
               (pal_token_balances.token_address = parameter_token_address)
               AND (
                  pal_token_balances.wallet_address = (
                     SELECT user_details.wallet_address
                     FROM user_details
                     WHERE (user_details.id = auth.uid())
                  )
               )
            )
      )
   )
);
end;$$;

ALTER FUNCTION "public"."check_view_granted"("parameter_token_address" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."check_write_granted"("parameter_token_address" "text") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$begin return auth.role() = 'authenticated'::text
and (
   (
      (
         SELECT pal_tokens.owner
         FROM pal_tokens
         WHERE (pal_tokens.token_address = parameter_token_address)
      ) = (
         SELECT user_details.wallet_address
         FROM user_details
         WHERE (user_details.id = auth.uid())
      )
   )
   or (
      (
         SELECT pal_tokens.write_token_required
         FROM pal_tokens
         WHERE (pal_tokens.token_address = parameter_token_address)
      ) <= (
         SELECT pal_token_balances.last_fetched_balance
         FROM pal_token_balances
         WHERE (
               (pal_token_balances.token_address = parameter_token_address)
               AND (
                  pal_token_balances.wallet_address = (
                     SELECT user_details.wallet_address
                     FROM user_details
                     WHERE (user_details.id = auth.uid())
                  )
               )
            )
      )
   )
);
end;$$;

ALTER FUNCTION "public"."check_write_granted"("parameter_token_address" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."decrement_token_favorite_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$begin
  update pal_tokens
  set
    favorite_count = favorite_count - 1
  where
    chain = 'base' and
    token_address = old.token_address;
  return null;
end;$$;

ALTER FUNCTION "public"."decrement_token_favorite_count"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."increment_token_favorite_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$begin
  update pal_tokens
  set
    favorite_count = favorite_count + 1
  where
    chain = 'base' and
    token_address = new.token_address;
  return null;
end;$$;

ALTER FUNCTION "public"."increment_token_favorite_count"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."increment_trading_fees_earned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$begin
  IF new.event_type = 1 THEN
    update pal_tokens
    set
      trading_fees_earned = trading_fees_earned + new.args[7]::numeric
    where
      chain = 'base' and
      token_address = new.args[2];
    update user_details
    set
      trading_fees_earned = trading_fees_earned + new.args[7]::numeric
    where
      wallet_address = new.args[1];
  END IF;
  return null;
end;$$;

ALTER FUNCTION "public"."increment_trading_fees_earned"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."new_pal_token"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$begin
  IF new.event_type = 0 THEN
    insert into pal_tokens (chain, token_address, owner, name, symbol) values (
      'base', new.args[2], new.args[1], new.args[3], new.args[4]
    ) ON CONFLICT (chain, token_address)
    DO NOTHING;
  END IF;
  return null;
end;$$;

ALTER FUNCTION "public"."new_pal_token"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."parse_contract_event"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
    v_receiver UUID;
    v_triggerer UUID;
BEGIN
    IF new.event_name = 'UserTokenCreated' THEN
        
        -- add activity
        insert into activities (
            chain, block_number, log_index, tx, wallet_address, token_address, activity_name, args
        ) values (
            new.chain, new.block_number, new.log_index, new.tx, new.args[1], new.args[2], new.event_name, new.args
        );
        
        -- add token info
        insert into tokens (
            chain, token_address, owner, name, symbol
        ) values (
            new.chain, new.args[2], new.args[1], new.args[3], new.args[4]
        );
        
        -- notify
        v_receiver := (SELECT user_id FROM users_public WHERE wallet_address = new.args[1]);
        IF v_receiver IS NOT NULL THEN
            insert into notifications (
                user_id, type, chain, token_address
            ) values (
                v_receiver, 0, new.chain, new.args[2]
            );
        END IF;

    ELSIF new.event_name = 'Trade' THEN

        -- add activity
        insert into activities (
            chain, block_number, log_index, tx, wallet_address, token_address, activity_name, args
        ) values (
            new.chain, new.block_number, new.log_index, new.tx, new.args[1], new.args[2], new.event_name, new.args
        );

        -- notify
        v_receiver := (SELECT user_id FROM users_public WHERE wallet_address = (
            SELECT owner FROM tokens WHERE chain = new.chain AND token_address = new.args[2]
        ));
        v_triggerer := (SELECT user_id FROM users_public WHERE wallet_address = new.args[1]);
        IF v_receiver IS NOT NULL AND v_receiver != v_triggerer THEN
            insert into notifications (
                user_id, triggerer, type, chain, token_address, amount
            ) values (
                v_receiver, v_triggerer, CASE WHEN new.args[3] = 'true' THEN 1 ELSE 2 END, new.chain, new.args[2], new.args[4]::numeric
            );
        END IF;

        -- buy
        IF new.args[3] = 'true' THEN
            
            -- update token info
            update tokens set
                supply = CASE WHEN new.chain = 'base' AND new.block_number < 8865668 THEN new.args[8]::numeric ELSE new.args[9]::numeric END,
                last_fetched_key_price = new.args[5]::numeric,
                total_trading_key_volume = total_trading_key_volume + new.args[5]::numeric,
                is_price_up = true,
                last_key_purchased_at = now()
            where chain = new.chain and token_address = new.args[2];

            -- update token holder info
            insert into token_holders (
                chain, token_address, wallet_address, last_fetched_balance
            ) values (
                new.chain, new.args[2], new.args[1], new.args[4]::numeric
            ) on conflict (chain, token_address, wallet_address) do update
                set last_fetched_balance = last_fetched_balance + new.args[4]::numeric;
            
            -- if token holder is new, add to token holder count
            IF NOT FOUND THEN
                update tokens set
                    holders = holders + 1
                where chain = new.chain and token_address = new.args[2];
            END IF;
            
            -- update wallet's total key balance
            insert into wallets (
                wallet_address, total_key_balance
            ) values (
                new.args[1], new.args[4]::numeric
            ) on conflict (wallet_address) do update
                set total_key_balance = wallets.total_key_balance + new.args[4]::numeric;

        -- sell
        ELSE
            -- update token info
            update tokens set
                supply = CASE WHEN new.chain = 'base' AND new.block_number < 8865668 THEN new.args[8]::numeric ELSE new.args[9]::numeric END,
                last_fetched_key_price = new.args[5]::numeric,
                total_trading_key_volume = total_trading_key_volume + new.args[5]::numeric,
                is_price_up = false
            where chain = new.chain and token_address = new.args[2];

            -- update token holder info
            WITH updated AS (
                UPDATE token_holders
                SET last_fetched_balance = last_fetched_balance - new.args[4]::numeric
                WHERE chain = new.chain
                AND token_address = new.args[2]
                AND wallet_address = new.args[1]
                RETURNING wallet_address, last_fetched_balance
            )
            DELETE FROM token_holders
            WHERE (wallet_address, last_fetched_balance) IN (
                SELECT wallet_address, last_fetched_balance FROM updated WHERE last_fetched_balance = 0
            );
            
            -- update wallet's total key balance
            update wallets set
                total_key_balance = total_key_balance - new.args[4]::numeric
            where wallet_address = new.args[1];
        END IF;
    END IF;
    RETURN NULL;
end;$$;

ALTER FUNCTION "public"."parse_contract_event"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$BEGIN
  new.updated_at := now();
  RETURN new;
END;$$;

ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_user_metadata_to_public"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if strpos(new.raw_user_meta_data ->> 'iss', 'twitter') > 0 then
    insert into public.users_public (user_id, display_name, avatar, avatar_thumb, avatar_stored, x_username)
    values (
      new.id,
      new.raw_user_meta_data ->> 'full_name',
      case 
        when strpos(new.raw_user_meta_data ->> 'avatar_url', '_normal') > 0 then
          replace(new.raw_user_meta_data ->> 'avatar_url', '_normal', '')
        else
          new.raw_user_meta_data ->> 'avatar_url'
      end,
      new.raw_user_meta_data ->> 'avatar_url',
      false,
      new.raw_user_meta_data ->> 'user_name'
    ) on conflict (user_id) do update
    set
      display_name = new.raw_user_meta_data ->> 'full_name',
      avatar = case 
        when strpos(new.raw_user_meta_data ->> 'avatar_url', '_normal') > 0 then
          replace(new.raw_user_meta_data ->> 'avatar_url', '_normal', '')
        else
          new.raw_user_meta_data ->> 'avatar_url'
      end,
      avatar_thumb = new.raw_user_meta_data ->> 'avatar_url',
      avatar_stored = false,
      x_username = new.raw_user_meta_data ->> 'user_name';
  else
    insert into public.users_public (user_id, display_name, avatar, avatar_thumb, avatar_stored)
    values (
      new.id,
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'avatar_url',
      false
    ) on conflict (user_id) do update
    set
      display_name = new.raw_user_meta_data ->> 'full_name',
      avatar = new.raw_user_meta_data ->> 'avatar_url',
      avatar_thumb = new.raw_user_meta_data ->> 'avatar_url',
      avatar_stored = false;
  end if;
  return new;
end;
$$;

ALTER FUNCTION "public"."set_user_metadata_to_public"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_last_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$begin
  update pal_tokens
  set
    last_message = new.author_name || ': ' || new.message,
    last_message_sent_at = now()
  where
    chain = 'base' and
    token_address = new.token_address;
  return null;
end;$$;

ALTER FUNCTION "public"."update_last_message"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_price_trend"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$BEGIN
  IF NEW.last_fetched_price > OLD.last_fetched_price THEN
    NEW.is_price_up := TRUE;
  ELSIF NEW.last_fetched_price < OLD.last_fetched_price THEN
    NEW.is_price_up := FALSE;
  END IF;
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."update_price_trend"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."activities" (
    "chain" "text" NOT NULL,
    "block_number" bigint NOT NULL,
    "log_index" bigint NOT NULL,
    "tx" "text" NOT NULL,
    "wallet_address" "text" NOT NULL,
    "token_address" "text" NOT NULL,
    "activity_name" "text" NOT NULL,
    "args" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."activities" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."token_chat_messages" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "token_address" "text" NOT NULL,
    "author" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "message_type" smallint NOT NULL,
    "message" "text",
    "rich" "jsonb",
    "translated" "jsonb",
    "author_name" "text",
    "author_avatar_url" "text",
    "chain" "text" DEFAULT 'base'::"text" NOT NULL
);

ALTER TABLE "public"."token_chat_messages" OWNER TO "postgres";

ALTER TABLE "public"."token_chat_messages" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."chat_messages_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."contract_events" (
    "chain" "text" NOT NULL,
    "block_number" bigint NOT NULL,
    "log_index" bigint NOT NULL,
    "tx" "text" NOT NULL,
    "event_name" "text" NOT NULL,
    "args" "text"[],
    "wallet_address" "text",
    "token_address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."contract_events" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."follows" (
    "follower_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "followee_id" "uuid" NOT NULL,
    "followed_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."follows" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "triggerer" "uuid",
    "type" smallint NOT NULL,
    "chain" "text",
    "token_address" "text",
    "amount" bigint,
    "post_id" bigint,
    "post_message" "text",
    "read" boolean DEFAULT false NOT NULL,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."notifications" OWNER TO "postgres";

ALTER TABLE "public"."notifications" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."notifications_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."old_pal_token_balances" (
    "token_address" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "wallet_address" "text" NOT NULL,
    "last_fetched_balance" numeric DEFAULT '0'::numeric NOT NULL,
    "chain" "text" DEFAULT 'base'::"text" NOT NULL
);

ALTER TABLE "public"."old_pal_token_balances" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."old_pal_tokens" (
    "token_address" "text" NOT NULL,
    "owner" "text" NOT NULL,
    "name" "text" NOT NULL,
    "symbol" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "view_token_required" numeric DEFAULT '1000000000000000000'::numeric NOT NULL,
    "write_token_required" numeric DEFAULT '1000000000000000000'::numeric NOT NULL,
    "last_fetched_price" numeric DEFAULT '68750000000000'::numeric NOT NULL,
    "last_message_sent_at" timestamp with time zone DEFAULT '-infinity'::timestamp with time zone NOT NULL,
    "hiding" boolean DEFAULT false NOT NULL,
    "trading_fees_earned" numeric DEFAULT '0'::numeric NOT NULL,
    "last_message" "text",
    "is_price_up" boolean,
    "favorite_count" integer DEFAULT 0 NOT NULL,
    "chain" "text" DEFAULT 'base'::"text" NOT NULL,
    "trading_volume" numeric DEFAULT '0'::numeric NOT NULL
);

ALTER TABLE "public"."old_pal_tokens" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."token_holders" (
    "chain" "text" NOT NULL,
    "token_address" "text" NOT NULL,
    "wallet_address" "text" NOT NULL,
    "last_fetched_balance" numeric DEFAULT '0'::numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);

ALTER TABLE "public"."token_holders" OWNER TO "postgres";

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
    "holder_count" integer DEFAULT 0 NOT NULL,
    "last_key_purchased_at" timestamp with time zone DEFAULT '-infinity'::timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);

ALTER TABLE "public"."tokens" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."tracked_event_blocks" (
    "chain" "text" NOT NULL,
    "block_number" bigint NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."tracked_event_blocks" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."users_public" (
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "wallet_address" "text",
    "metadata" "jsonb",
    "avatar" "text",
    "display_name" "text",
    "total_earned_trading_fees" numeric DEFAULT '0'::numeric NOT NULL,
    "avatar_thumb" "text",
    "avatar_stored" boolean DEFAULT false NOT NULL,
    "stored_avatar" "text",
    "stored_avatar_thumb" "text",
    "x_username" "text",
    "follower_count" integer DEFAULT 0 NOT NULL,
    "following_count" integer DEFAULT 0 NOT NULL,
    "blocked" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone
);

ALTER TABLE "public"."users_public" OWNER TO "postgres";

ALTER TABLE ONLY "public"."activities"
    ADD CONSTRAINT "activities_pkey" PRIMARY KEY ("chain", "block_number", "log_index");

ALTER TABLE ONLY "public"."token_chat_messages"
    ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."contract_events"
    ADD CONSTRAINT "contract_events_pkey" PRIMARY KEY ("chain", "block_number", "log_index");

ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_pkey" PRIMARY KEY ("follower_id", "followee_id");

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."old_pal_token_balances"
    ADD CONSTRAINT "pal_token_balances_pkey" PRIMARY KEY ("token_address", "wallet_address", "chain");

ALTER TABLE ONLY "public"."old_pal_tokens"
    ADD CONSTRAINT "pal_tokens_pkey" PRIMARY KEY ("token_address", "chain");

ALTER TABLE ONLY "public"."token_holders"
    ADD CONSTRAINT "token_holders_pkey" PRIMARY KEY ("chain", "token_address", "wallet_address");

ALTER TABLE ONLY "public"."tokens"
    ADD CONSTRAINT "tokens_pkey" PRIMARY KEY ("chain", "token_address");

ALTER TABLE ONLY "public"."tracked_event_blocks"
    ADD CONSTRAINT "tracked_event_blocks_pkey" PRIMARY KEY ("chain");

ALTER TABLE ONLY "public"."users_public"
    ADD CONSTRAINT "user_wallets_wallet_address_key" UNIQUE ("wallet_address");

ALTER TABLE ONLY "public"."users_public"
    ADD CONSTRAINT "users_public_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."users_public"
    ADD CONSTRAINT "users_public_wallet_address_key" UNIQUE ("wallet_address");

CREATE OR REPLACE TRIGGER "parse_contract_event" AFTER INSERT ON "public"."contract_events" FOR EACH ROW EXECUTE FUNCTION "public"."parse_contract_event"();

CREATE OR REPLACE TRIGGER "set_users_public_updated_at" BEFORE UPDATE ON "public"."users_public" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "update_last_message" AFTER INSERT ON "public"."token_chat_messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_last_message"();

CREATE OR REPLACE TRIGGER "update_price_trend" BEFORE UPDATE ON "public"."old_pal_tokens" FOR EACH ROW EXECUTE FUNCTION "public"."update_price_trend"();

ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_followee_id_fkey" FOREIGN KEY ("followee_id") REFERENCES "public"."users_public"("user_id");

ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "public"."users_public"("user_id");

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_triggerer_fkey" FOREIGN KEY ("triggerer") REFERENCES "public"."users_public"("user_id");

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users_public"("user_id");

ALTER TABLE ONLY "public"."token_chat_messages"
    ADD CONSTRAINT "token_chat_messages_author_fkey" FOREIGN KEY ("author") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."users_public"
    ADD CONSTRAINT "users_public_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");

ALTER TABLE "public"."activities" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow anon select" ON "public"."old_pal_token_balances" FOR SELECT USING (true);

CREATE POLICY "allow anon select" ON "public"."old_pal_tokens" FOR SELECT USING (true);

CREATE POLICY "allow anon select" ON "public"."users_public" FOR SELECT USING (true);

CREATE POLICY "can follow only follower" ON "public"."follows" FOR INSERT TO "authenticated" WITH CHECK ((("follower_id" = "auth"."uid"()) AND ("follower_id" <> "followee_id")));

CREATE POLICY "can unfollow only follower" ON "public"."follows" FOR DELETE TO "authenticated" USING (("follower_id" = "auth"."uid"()));

ALTER TABLE "public"."contract_events" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."follows" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."old_pal_token_balances" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."old_pal_tokens" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."token_chat_messages" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."token_holders" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tokens" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tracked_event_blocks" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "update pal token's metadata" ON "public"."old_pal_tokens" FOR UPDATE TO "authenticated" USING (("owner" = ( SELECT "users_public"."wallet_address"
   FROM "public"."users_public"
  WHERE ("users_public"."user_id" = "auth"."uid"())))) WITH CHECK (("owner" = ( SELECT "users_public"."wallet_address"
   FROM "public"."users_public"
  WHERE ("users_public"."user_id" = "auth"."uid"()))));

ALTER TABLE "public"."users_public" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "view everyone" ON "public"."follows" FOR SELECT USING (true);

CREATE POLICY "view everyone" ON "public"."users_public" FOR SELECT USING (true);

CREATE POLICY "view only holder or owner" ON "public"."token_chat_messages" FOR SELECT TO "authenticated" USING (((( SELECT "old_pal_tokens"."owner"
   FROM "public"."old_pal_tokens"
  WHERE ("old_pal_tokens"."token_address" = "token_chat_messages"."token_address")) = ( SELECT "users_public"."wallet_address"
   FROM "public"."users_public"
  WHERE ("users_public"."user_id" = "auth"."uid"()))) OR (( SELECT "old_pal_tokens"."view_token_required"
   FROM "public"."old_pal_tokens"
  WHERE ("old_pal_tokens"."token_address" = "token_chat_messages"."token_address")) <= ( SELECT "old_pal_token_balances"."last_fetched_balance"
   FROM "public"."old_pal_token_balances"
  WHERE (("old_pal_token_balances"."token_address" = "token_chat_messages"."token_address") AND ("old_pal_token_balances"."wallet_address" = ( SELECT "users_public"."wallet_address"
           FROM "public"."users_public"
          WHERE ("users_public"."user_id" = "auth"."uid"()))))))));

CREATE POLICY "write only holder or owner" ON "public"."token_chat_messages" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "author") AND ((( SELECT "old_pal_tokens"."owner"
   FROM "public"."old_pal_tokens"
  WHERE ("old_pal_tokens"."token_address" = "token_chat_messages"."token_address")) = ( SELECT "users_public"."wallet_address"
   FROM "public"."users_public"
  WHERE ("users_public"."user_id" = "auth"."uid"()))) OR (( SELECT "old_pal_tokens"."write_token_required"
   FROM "public"."old_pal_tokens"
  WHERE ("old_pal_tokens"."token_address" = "token_chat_messages"."token_address")) <= ( SELECT "old_pal_token_balances"."last_fetched_balance"
   FROM "public"."old_pal_token_balances"
  WHERE (("old_pal_token_balances"."token_address" = "token_chat_messages"."token_address") AND ("old_pal_token_balances"."wallet_address" = ( SELECT "users_public"."wallet_address"
           FROM "public"."users_public"
          WHERE ("users_public"."user_id" = "auth"."uid"())))))))));

REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."check_view_granted"("parameter_token_address" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_view_granted"("parameter_token_address" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_view_granted"("parameter_token_address" "text") TO "service_role";

GRANT ALL ON FUNCTION "public"."check_write_granted"("parameter_token_address" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_write_granted"("parameter_token_address" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_write_granted"("parameter_token_address" "text") TO "service_role";

GRANT ALL ON FUNCTION "public"."decrement_token_favorite_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_token_favorite_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_token_favorite_count"() TO "service_role";

GRANT ALL ON FUNCTION "public"."increment_token_favorite_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."increment_token_favorite_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_token_favorite_count"() TO "service_role";

GRANT ALL ON FUNCTION "public"."increment_trading_fees_earned"() TO "anon";
GRANT ALL ON FUNCTION "public"."increment_trading_fees_earned"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_trading_fees_earned"() TO "service_role";

GRANT ALL ON FUNCTION "public"."new_pal_token"() TO "anon";
GRANT ALL ON FUNCTION "public"."new_pal_token"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."new_pal_token"() TO "service_role";

GRANT ALL ON FUNCTION "public"."parse_contract_event"() TO "anon";
GRANT ALL ON FUNCTION "public"."parse_contract_event"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."parse_contract_event"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_user_metadata_to_public"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_user_metadata_to_public"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_user_metadata_to_public"() TO "service_role";

GRANT ALL ON FUNCTION "public"."update_last_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_last_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_last_message"() TO "service_role";

GRANT ALL ON FUNCTION "public"."update_price_trend"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_price_trend"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_price_trend"() TO "service_role";

GRANT ALL ON TABLE "public"."activities" TO "anon";
GRANT ALL ON TABLE "public"."activities" TO "authenticated";
GRANT ALL ON TABLE "public"."activities" TO "service_role";

GRANT ALL ON TABLE "public"."token_chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."token_chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."token_chat_messages" TO "service_role";

GRANT ALL ON SEQUENCE "public"."chat_messages_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."chat_messages_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."chat_messages_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."contract_events" TO "anon";
GRANT ALL ON TABLE "public"."contract_events" TO "authenticated";
GRANT ALL ON TABLE "public"."contract_events" TO "service_role";

GRANT ALL ON TABLE "public"."follows" TO "anon";
GRANT ALL ON TABLE "public"."follows" TO "authenticated";
GRANT ALL ON TABLE "public"."follows" TO "service_role";

GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";

GRANT ALL ON SEQUENCE "public"."notifications_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."notifications_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."notifications_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."old_pal_token_balances" TO "anon";
GRANT ALL ON TABLE "public"."old_pal_token_balances" TO "authenticated";
GRANT ALL ON TABLE "public"."old_pal_token_balances" TO "service_role";

GRANT ALL ON TABLE "public"."old_pal_tokens" TO "anon";
GRANT ALL ON TABLE "public"."old_pal_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."old_pal_tokens" TO "service_role";

GRANT ALL ON TABLE "public"."token_holders" TO "anon";
GRANT ALL ON TABLE "public"."token_holders" TO "authenticated";
GRANT ALL ON TABLE "public"."token_holders" TO "service_role";

GRANT ALL ON TABLE "public"."tokens" TO "anon";
GRANT ALL ON TABLE "public"."tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."tokens" TO "service_role";

GRANT ALL ON TABLE "public"."tracked_event_blocks" TO "anon";
GRANT ALL ON TABLE "public"."tracked_event_blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."tracked_event_blocks" TO "service_role";

GRANT ALL ON TABLE "public"."users_public" TO "anon";
GRANT ALL ON TABLE "public"."users_public" TO "authenticated";
GRANT ALL ON TABLE "public"."users_public" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;
