import { DomNode, el } from "@common-module/app";
import SupabaseManager from "../../SupabaseManager.js";
import TokenInfoCacher from "../../cacher/TokenInfoCacher.js";
import UserDetailsCacher from "../../cacher/UserDetailsCacher.js";
import Activity, { eventToActivity, EventType } from "../../data/Activity.js";
import TokenCreatedActivityItem from "./TokenCreatedActivityItem.js";
import TradeActivityItem from "./TradeActivityItem.js";
import ListLoading from "../ListLoading.js";

export default class ActivityList extends DomNode {
  private list: DomNode;
  private loadingComponent: ListLoading | undefined;

  constructor() {
    super(".activity-list");
    this.append(
      this.list = el("ul", this.loadingComponent = new ListLoading()),
    );
    this.loadingComponent.on("delete", () => this.loadingComponent = undefined);
  }

  public add(activity: Activity): TokenCreatedActivityItem | TradeActivityItem {
    if (activity.eventType === EventType.TokenCreated) {
      const item = new TokenCreatedActivityItem(activity).appendTo(this.list);
      return item;
    } else if (activity.eventType === EventType.Trade) {
      const item = new TradeActivityItem(activity).appendTo(this.list);
      return item;
    } else {
      throw new Error("Unknown event type");
    }
  }

  public async load(filter: {
    walletAddresses?: string[];
    tokenAddresses?: string[];
  }) {
    const select = SupabaseManager.supabase.from(
      "pal_contract_events",
    ).select("*")
      .limit(50);

    if (filter.walletAddresses) {
      select.in("wallet_address", filter.walletAddresses);
    }
    if (filter.tokenAddresses) {
      select.in("token_address", filter.tokenAddresses);
    }
    const { data, error } = await select.order("block_number", {
      ascending: false,
    });
    if (error) {
      throw error;
    }
    this.list.empty();
    if (data) {
      const activityList: Activity[] = [];
      const tokenAddresses = new Set<string>();
      const walletAddresses = new Set<string>();

      for (const event of data) {
        const activity = eventToActivity(
          event.event_type,
          event.block_number,
          event.args,
        );
        if (activity.eventType === EventType.TokenCreated) {
          tokenAddresses.add(activity.address);
          walletAddresses.add(activity.owner);
        } else if (activity.eventType === EventType.Trade) {
          tokenAddresses.add(activity.token);
          walletAddresses.add(activity.trader);
        }
        activityList.push(activity);
      }

      const tokenInfoSet = await TokenInfoCacher.load(
        Array.from(tokenAddresses),
      );
      for (const tokenInfo of tokenInfoSet) {
        walletAddresses.add(tokenInfo.owner);
      }
      await UserDetailsCacher.load(Array.from(walletAddresses));

      if (!this.deleted) {
        this.list.empty();
        for (const activity of activityList) {
          this.add(activity);
        }
      }
    }
  }

  public loaded() {
    this.loadingComponent?.delete();
  }

  public active(): void {
    this.addClass("active");
  }

  public inactive(): void {
    this.deleteClass("active");
  }
}
