import {HTTPError} from './security.mjs';
export async function subscriptionStatus(db,household,now){
 const row=await db.prepare('SELECT MAX(expires_ms) expires_ms FROM subscriptions WHERE household_id=? AND revoked=0 AND expires_ms>?').bind(household,now).first();
 const owned=await db.prepare('SELECT original_id FROM subscriptions WHERE household_id=? ORDER BY original_id').bind(household).all();
 return {active:!!row?.expires_ms,expires_ms:row?.expires_ms??null,original_ids:owned.results.map(value=>value.original_id)};
}
export async function subscriptionOwner(db,originalID){
 if(typeof originalID!=='string'||!originalID)return null;
 return db.prepare('SELECT household_id,environment FROM subscriptions WHERE original_id=?').bind(originalID).first();
}
export async function saveTransaction(db,transaction,household,env,now,{appTransaction}={}){
 if(transaction.bundleId!==env.BUNDLE_ID||transaction.productId!==env.PRODUCT_ID||transaction.type!=='Auto-Renewable Subscription'||!['Sandbox','Production'].includes(transaction.environment))throw new HTTPError(403,'Wrong subscription product');
 if(!Number.isSafeInteger(transaction.signedDate)||transaction.signedDate>now+300000||!Number.isSafeInteger(transaction.expiresDate)||typeof transaction.originalTransactionId!=='string'||!transaction.originalTransactionId||typeof transaction.transactionId!=='string'||!transaction.transactionId)throw new HTTPError(403,'Invalid transaction');
 const owner=await subscriptionOwner(db,transaction.originalTransactionId);
 if(owner&&(owner.household_id!==household||owner.environment!==transaction.environment))throw new HTTPError(409,'Subscription already bound');
 const sameAccount=typeof transaction.appAccountToken==='string'&&transaction.appAccountToken.toLowerCase()===household.toLowerCase();
 if(!owner&&!sameAccount){
  // A permanent deletion removes the old binding. A fresh, independently
  // verified app receipt must prove the same Apple account before restoring it.
  if(typeof transaction.appAccountToken!=='string'||!/^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.test(transaction.appAccountToken)||!appTransaction||appTransaction.bundleId!==env.BUNDLE_ID||appTransaction.receiptType!==transaction.environment||typeof appTransaction.appTransactionId!=='string'||!appTransaction.appTransactionId||appTransaction.appTransactionId!==transaction.appTransactionId||!Number.isSafeInteger(appTransaction.receiptCreationDate)||appTransaction.receiptCreationDate<now-3600000||appTransaction.receiptCreationDate>now+300000||transaction.expiresDate<=now||transaction.revocationDate||transaction.isUpgraded)throw new HTTPError(403,'Restore requires a current matching Apple account');
  if(typeof transaction.appAccountToken==='string'&&await db.prepare('SELECT 1 FROM households WHERE lower(id)=?').bind(transaction.appAccountToken.toLowerCase()).first())throw new HTTPError(409,'Sign in to the original household');
 }
 await db.prepare(`INSERT INTO subscriptions VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(original_id) DO UPDATE SET transaction_id=excluded.transaction_id,expires_ms=excluded.expires_ms,revoked=excluded.revoked,signed_ms=excluded.signed_ms WHERE subscriptions.household_id=excluded.household_id AND subscriptions.environment=excluded.environment AND excluded.signed_ms>=subscriptions.signed_ms`).bind(transaction.originalTransactionId,household,transaction.transactionId,transaction.productId,transaction.environment,transaction.expiresDate,transaction.revocationDate?1:0,transaction.signedDate).run();
 // The primary key arbitrates concurrent restore attempts. A losing household
 // must never receive a fulfillment acknowledgment.
 const saved=await subscriptionOwner(db,transaction.originalTransactionId);
 if(saved?.household_id!==household||saved.environment!==transaction.environment)throw new HTTPError(409,'Subscription already bound');
 return {...await subscriptionStatus(db,household,now),transaction_id:transaction.transactionId};
}
