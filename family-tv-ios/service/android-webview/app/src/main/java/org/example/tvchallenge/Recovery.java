package org.example.tvchallenge;

import android.app.*;
import android.app.job.*;
import android.content.*;
import android.os.*;
import android.provider.Settings;

/** 系统支持的恢复：精确非唤醒闹钟+持久Job。权限由家长和系统管理，恢复任务不改写无障碍设置。 */
final class Recovery {
 private static final int JOB=31001;
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
  if(Settings.Secure.getInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,0)!=1){NativeState.log(c,"RECOVERY_PERMISSION_DISABLED awaiting_parent");return;}
  if(ControlAccessibilityService.instance!=null){if(!MonitorService.running)MonitorService.start(c);return;}
  NativeState.log(c,"RECOVERY_AWAITING_ACCESSIBILITY_BINDING");
 }
}
