import { ethers } from "https://esm.sh/ethers@6.7.0";
import Contract from "./Contract.ts";
import PalArtifact from "./abi/pal/Pal.json" assert { type: "json" };
import { Pal } from "./abi/pal/Pal.ts";

export default class PalContract extends Contract<Pal> {
  public tokenCreatedEventFilter: ethers.TopicFilter | undefined;
  public tradeEventFilter: ethers.TopicFilter | undefined;

  constructor(signer: ethers.Signer) {
    super(Deno.env.get("PAL_ADDRESS")!, PalArtifact.abi, signer);
  }

  public async getEvents(startBlock: number, endBlock: number) {
    if (!this.tokenCreatedEventFilter || !this.tradeEventFilter) {
      this.tokenCreatedEventFilter = await this.ethersContract.filters
        .UserTokenCreated()
        .getTopicFilter();
      this.tradeEventFilter = await this.ethersContract.filters.Trade()
        .getTopicFilter();
    }

    return await this.ethersContract.queryFilter(
      [this.tokenCreatedEventFilter.concat(this.tradeEventFilter)] as any,
      startBlock,
      endBlock,
    );
  }

  public async getBuyPrice(tokenAddress: string, amount: bigint) {
    return await this.ethersContract.getBuyPrice(tokenAddress, amount);
  }
}
