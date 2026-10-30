import {createHandler,cleanup} from './handler.mjs';
import {verifyTransaction,verifyNotification,verifyAppTransaction} from './apple.mjs';
const handle=createHandler({verifyTransaction,verifyNotification,verifyAppTransaction});
export default {
 fetch:handle,
 async scheduled(event,env,ctx){ctx.waitUntil(cleanup(env));}
};
