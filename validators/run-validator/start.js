import { sync_db_with_blockchain } from "./lib/sync.js";
import { process_requests } from "./lib/process.js";
import { load_database } from "./lib/db.js";
import { load_aleo_account } from "./lib/aleo.js";
import { LiveRpcProvider } from "./lib/rpc.js";

import {
  private_key_error_msg, private_key_success_msg, refresh_error_msg
} from "../config/errors.js"

import 'dotenv/config';


const load_env = async () => {
  const refresh_period_s = Number(process.env["REFRESH_PERIOD_S"]);
  if (isNaN(refresh_period_s) || refresh_period_s < 0) {
    throw new Error(refresh_error_msg);
  }
  const rpc_provider = LiveRpcProvider(process.env["RPC_URL"]);
  try {
    account = await load_aleo_account(process.env["PRIVATE_KEY"]);
    address = account.address().to_string();
    console.log(private_key_success_msg, address);
    return { account, refresh_period_s, rpc_provider };
  } catch {
    throw new Error(private_key_error_msg);
  }
};


const sync_and_process = async (rpc_provider, db, account) => {
  await sync_db_with_blockchain(rpc_provider, db, account);
  await process_requests(rpc_provider, db, account);
}


const main = async () => {
  const { account, refresh_period_s, rpc_provider } = await load_env();
  const db = await load_database();
  while (true) {
    try {
      await sync_and_process(rpc_provider, db, account);
    } catch (e) {
      console.log(e);
    }
    await new Promise(r => setTimeout(r, refresh_period_s * 1000));
  }
}


await main();