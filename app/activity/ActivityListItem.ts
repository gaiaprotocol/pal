import {
  AvatarUtil,
  DateUtil,
  DomNode,
  el,
  msgs,
  Router,
  StringUtil,
} from "@common-module/app";
import { ethers } from "ethers";
import BlockTimeManager from "../BlockTimeManager.js";
import Activity from "../database-interface/Activity.js";
import { TokenInfoPopup } from "../index.js";

export default class ActivityListItem extends DomNode {
  constructor(activity: Activity) {
    super(".activity-list-item");

    const tokenImage = el(".token-image", {
      click: () =>
        new TokenInfoPopup(
          activity.chain,
          activity.token_address,
          undefined,
          activity.token,
        ),
    });

    AvatarUtil.selectLoadable(tokenImage, [
      activity.token?.image_thumb,
      activity.token?.stored_image_thumb,
    ]);

    const user = el("a", activity.user?.display_name, {
      click: () => Router.go(`/${activity.user?.x_username}`),
    });

    const date = el(
      "span.date",
      DateUtil.fromNow(
        BlockTimeManager.blockToTime(activity.chain, activity.block_number),
      ),
    );

    if (activity.activity_name === "UserTokenCreated") {
      const token = el("a", activity.token?.name, {
        click: () =>
          new TokenInfoPopup(
            activity.chain,
            activity.token_address,
            undefined,
            activity.token,
          ),
      });

      this.append(
        el("header", tokenImage),
        el(
          "main",
          el(
            "p.description",
            ...msgs("activity-list-item-created-token-text", { user, token }),
          ),
          el(".info", date),
        ),
      );
    }

    if (activity.activity_name === "Trade") {
      const symbol = el("a", activity.token?.symbol, {
        click: () =>
          new TokenInfoPopup(
            activity.chain,
            activity.token_address,
            undefined,
            activity.token,
          ),
      });

      const isBuy = activity.args[2] === "true";
      const amount = StringUtil.numberWithCommas(
        ethers.formatEther(activity.args[3]),
      );
      const price = StringUtil.numberWithCommas(
        ethers.formatEther(activity.args[4]),
      );

      const traderAvatar = el(".trader-avatar", {
        click: () => Router.go(`/${activity.user?.x_username}`),
      });

      AvatarUtil.selectLoadable(traderAvatar, [
        activity.user?.avatar_thumb,
        activity.user?.stored_avatar_thumb,
      ]);

      this.append(
        el("header", traderAvatar, tokenImage),
        el(
          "main",
          el(
            "p.description",
            ...msgs(
              isBuy
                ? "activity-list-item-bought-token-text"
                : "activity-list-item-sold-token-text",
              { user, symbol, amount },
            ),
          ),
          el(
            ".info",
            el("span.price" + (isBuy ? ".up" : ".down"), price, " ETH, "),
            date,
          ),
        ),
      );
    }
  }
}
