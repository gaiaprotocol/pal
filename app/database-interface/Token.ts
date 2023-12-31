export default interface Token {
  chain: string;
  token_address: string;
  owner: string;
  name: string;
  symbol: string;
  image: string;
  metadata?: any;
  supply: string;
  last_fetched_key_price: string;
  total_trading_key_volume: string;
  is_price_up: boolean;
  last_message: string;
  last_message_sent_at: string;
  holder_count: number;
  last_key_purchased_at: string;
  created_at: string;
  updated_at?: string;
}

export const TokenSelectQuery =
  "*, supply::text, last_fetched_key_price::text, total_trading_key_volume::text";
