import { ethers } from "ethers";
import Config from "../Config.js";

class BlockTimeCacher {
  private blockNumber!: number;
  private blockTime!: number;

  public async init() {
    const provider = new ethers.JsonRpcProvider(Config.palRPC);
    const block = await provider.getBlock("latest");
    this.blockNumber = block!.number;
    this.blockTime = block!.timestamp * 1000;
  }

  public blockToTime(blockNumber: number): number {
    // Base chain
    return this.blockTime + (blockNumber - this.blockNumber) * 2 * 1000;
  }
}

export default new BlockTimeCacher();
