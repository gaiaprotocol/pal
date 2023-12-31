import { createClient } from "https://esm.sh/@supabase/supabase-js@2.31.0";
import { response, responseError, serveWithOptions } from "../_shared/cors.ts";
import { getTokenInfo } from "../_shared/token.ts";
import { getSignedUser } from "../_shared/user.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

serveWithOptions(async (req) => {
  const user = await getSignedUser(req);
  if (!user) {
    return responseError("Unauthorized");
  }

  const { data: userWallet } = await supabase
    .from("user_details")
    .select("wallet_address")
    .eq("id", user.id)
    .single();

  if (!userWallet) {
    return responseError("No wallet address");
  }

  const { tokenAddress } = await req.json();
  try {
    if (tokenAddress) {
      const tokenInfo = await getTokenInfo(
        tokenAddress,
        userWallet.wallet_address,
      );

      if (userWallet.wallet_address !== tokenInfo.owner) {
        throw new Error("Invalid owner");
      }

      const { error } = await supabase.from("pal_tokens").update({
        hiding: true,
      }).eq("token_address", tokenAddress);

      if (error) {
        throw error;
      }

      return response({});
    }
    throw new Error("Invalid request");
  } catch (e) {
    return responseError(e.message);
  }
});
