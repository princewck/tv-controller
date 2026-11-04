// Test-only Worker, never deployed or imported by the production entrypoint.
import fixture from './fixtures/apple-verifier.json';
import {X509Certificate} from 'node:crypto';
export default {async fetch(){
 try{
  const {SignedDataVerifier,Environment}=await import('@apple/app-store-server-library');
  const verifier=new SignedDataVerifier([Buffer.from(fixture.test_root,'base64')],false,Environment.SANDBOX,'com.example',1234);
  const transaction=await verifier.verifyAndDecodeTransaction(fixture.signed_transaction);
  const appVerifier=new SignedDataVerifier([Buffer.from(fixture.app_test_root,'base64')],false,Environment.SANDBOX,'com.example',531412);
  const appTransaction=await appVerifier.verifyAndDecodeAppTransaction(fixture.signed_app_transaction);
  const appParts=fixture.signed_app_transaction.split('.');const appPayload=JSON.parse(Buffer.from(appParts[1],'base64url'));appPayload.appTransactionId='tampered';appParts[1]=Buffer.from(JSON.stringify(appPayload)).toString('base64url');
  let appRejected=false;try{await appVerifier.verifyAndDecodeAppTransaction(appParts.join('.'));}catch{appRejected=true;}
  let identityRejected=0;for(const value of [fixture.wrong_bundle_app_transaction,fixture.wrong_environment_app_transaction]){try{await appVerifier.verifyAndDecodeAppTransaction(value);}catch{identityRejected++;}}
  if(!appRejected||identityRejected!==2)throw new Error('Invalid app receipt accepted');
  const parts=fixture.signed_transaction.split('.');const payload=JSON.parse(Buffer.from(parts[1],'base64url'));payload.bundleId='tampered';parts[1]=Buffer.from(JSON.stringify(payload)).toString('base64url');
  let rejected=false;try{await verifier.verifyAndDecodeTransaction(parts.join('.'));}catch{rejected=true;}
  if(!rejected)throw new Error('Tampered signature accepted');
  const real=new SignedDataVerifier([Buffer.from(fixture.REAL_APPLE_ROOT_BASE64_ENCODED,'base64')],true,Environment.PRODUCTION,'com.example',1234);
  await real.verifyCertificateChain(real.rootCertificates,new X509Certificate(Buffer.from(fixture.REAL_APPLE_SIGNING_CERTIFICATE_BASE64_ENCODED,'base64')),new X509Certificate(Buffer.from(fixture.REAL_APPLE_INTERMEDIATE_BASE64_ENCODED,'base64')),new Date(1761962975000));
  return Response.json({signed_app_transaction_verified:appTransaction.appTransactionId==='71134',tampered_app_signature_rejected:appRejected,wrong_app_bundle_and_environment_rejected:identityRejected===2,signed_transaction_verified:transaction.bundleId==='com.example',tampered_signature_rejected:rejected,real_apple_chain_and_online_ocsp:true});
 }catch(e){return Response.json({error:e.message,status:e.status,cause:e.cause?.message}, {status:500});}
}};
