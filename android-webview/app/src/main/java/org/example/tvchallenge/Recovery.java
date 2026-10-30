package org.example.tvchallenge;

import android.app.*;
import android.app.job.*;
import android.content.*;
import android.os.*;
import android.provider.Settings;
import java.util.*;

/** 系统支持的恢复：精确非唤醒闹钟+持久Job。只重新绑定仍在启用列表的自身服务，不复活用户关闭的权限。 */
final class Recovery {
 private static final int JOB=31001;
 private static boolean repairing;
 static PendingIntent alarm(Context c){return PendingIntent.getBroadcast(c,31001,new Intent(c,RecoveryReceiver.class),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);}
 static void schedule(Context c){
  if(!NativeState.enabled(c))return;
  AlarmManager a=c.getSystemService(AlarmManager.class);
  if(Build.VERSION.SDK_INT<31||a.canScheduleExactAlarms())a.setExact(AlarmManager.ELAPSED_REALTIME,SystemClock.elapsedRealtime()+60000,alarm(c));
  else a.set(AlarmManager.ELAPSED_REALTIME,SystemClock.elapsedRealtime()+60000,alarm(c));
  JobScheduler jobs=c.getSystemService(JobScheduler.class);
  if(jobs.getPendingJob(JOB)==null)jobs.schedule(new JobInfo.Builder(JOB,new ComponentName(c,RecoveryJob.class)).setPeriodic(15*60000L).setPersisted(true).build());
 }
 static void cancel(Context c){c.getSystemService(AlarmManager.class).cancel(alarm(c));c.getSystemService(JobScheduler.class).cancel(JOB);}
 static void check(Context context){
  Context c=context.getApplicationContext();if(!NativeState.enabled(c))return;
  schedule(c);
  if(ControlAccessibilityService.instance!=null){if(!MonitorService.running)MonitorService.start(c);return;}
  String enabled=Settings.Secure.getString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
  ComponentName own=new ComponentName(c,ControlAccessibilityService.class);List<String> keep=new ArrayList<>();String entry=null;
  if(enabled!=null)for(String s:enabled.split(":")){if(own.equals(ComponentName.unflattenFromString(s)))entry=s;else if(!s.isEmpty())keep.add(s);}
  // 崩溃时enabled项仍在；用户主动撤销会从列表删除，这时不再打开。
  if(entry==null){NativeState.log(c,"RECOVERY_PERMISSION_DISABLED awaiting_parent");return;}
  synchronized(Recovery.class){if(repairing)return;repairing=true;}
  final String restore=entry;
  try{
   Settings.Secure.putString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,String.join(":",keep));
   new Handler(Looper.getMainLooper()).postDelayed(()->{
    try{
     if(!NativeState.enabled(c))return;
     String current=Settings.Secure.getString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);List<String> entries=new ArrayList<>();
     if(current!=null&&!current.isEmpty())entries.addAll(Arrays.asList(current.split(":")));
     boolean contains=false;for(String s:entries)if(own.equals(ComponentName.unflattenFromString(s)))contains=true;
     if(!contains)entries.add(restore);
     Settings.Secure.putString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,String.join(":",entries));
     Settings.Secure.putInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,1);
     NativeState.log(c,"RECOVERY_REBOUND_REQUESTED");MonitorService.start(c);
    }catch(RuntimeException e){NativeState.log(c,"RECOVERY_FAILED "+e.getClass().getSimpleName());}
    finally{synchronized(Recovery.class){repairing=false;}}
   },700);
  }catch(RuntimeException e){synchronized(Recovery.class){repairing=false;}NativeState.log(c,"RECOVERY_FAILED "+e.getClass().getSimpleName());}
 }
}
