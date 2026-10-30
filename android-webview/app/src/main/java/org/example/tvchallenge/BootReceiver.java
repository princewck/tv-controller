package org.example.tvchallenge;
import android.content.*;
/** 系统开机/应用升级恢复；凭证和权限均存于电视，完全不使用ADB连接。 */
public class BootReceiver extends BroadcastReceiver {
 @Override public void onReceive(Context context,Intent intent){
  String action=intent.getAction();
  if(Intent.ACTION_BOOT_COMPLETED.equals(action)||Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)){
   NativeState.log(context,"BOOT_RECEIVER "+action);if(NativeState.enabled(context)){Recovery.schedule(context);Recovery.check(context);}
  }
 }
}
