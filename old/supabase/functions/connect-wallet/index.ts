import { createClient } from "https://esm.sh/@supabase/supabase-js@2.31.0";
import { ethers } from "https://esm.sh/ethers@6.7.0";
import { response, responseError, serveWithOptions } from "../_shared/cors.ts";
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

  const { walletAddress, signedMessage } = await req.json();
  try {
    if (walletAddress && signedMessage) {
      const { data: nonceData, error: nonceError } = await supabase
        .from("nonce")
        .select()
        .eq("id", user.id);

      if (nonceError) {
        throw new Error(nonceError.message);
      }

      if (!nonceData || !nonceData[0]) {
        throw new Error("Nonce not found");
      }

      if (nonceData[0]?.wallet_address !== walletAddress) {
        throw new Error("Invalid wallet address");
      }

      const verifiedAddress = ethers.verifyMessage(
        `Connect to Pal\nNonce: ${nonceData[0]?.nonce}`,
        signedMessage,
      );

      if (walletAddress !== verifiedAddress) {
        throw new Error("Invalid signature");
      }

      // Delete nonce
      await supabase
        .from("nonce")
        .delete()
        .eq("id", user.id);

      const { error: updateError } = await supabase
        .from("user_details")
        .update({
          wallet_address: null,
        })
        .eq("wallet_address", walletAddress);

      if (updateError) {
        throw new Error(updateError.message);
      }

      const { error: updateError2 } = await supabase
        .from("user_details")
        .upsert({
          id: user.id,
          wallet_address: walletAddress,
          display_name: user.user_metadata.full_name,
          profile_image: user.user_metadata.avatar_url,
          metadata: {
            xUsername: user.user_metadata.user_name,
          },
        })
        .eq("id", user.id);

      if (updateError2) {
        throw new Error(updateError2.message);
      }

      return response({});
    }
    throw new Error("Invalid request");
  } catch (e) {
    return responseError(e.message);
  }
});
