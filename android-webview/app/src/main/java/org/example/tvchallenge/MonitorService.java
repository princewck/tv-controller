package org.example.tvchallenge;

import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.media.*;
import android.net.Uri;
import android.os.*;
import org.json.JSONObject;
import javax.net.ssl.HttpsURLConnection;
import java.io.*;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

/** 原生纯出站客户端：应用UID、私有凭证、开机恢复；运行与ADB进程/端口无关。 */
public class MonitorService extends Service {
 static volatile boolean running;
 static volatile int foregroundType;
 private volatile boolean stop;
 private Thread worker;
 private AudioFocusRequest audioFocus;
 private boolean hasFocus;
 private long lastLaunch;
 static void start(Context c){
  try{c.startForegroundService(new Intent(c,MonitorService.class));}
  catch(RuntimeException e){NativeState.log(c,"SERVICE_START_FAILED "+e.getClass().getSimpleName());}
 }
 @Override public void onCreate(){
  super.onCreate();NotificationManager nm=getSystemService(NotificationManager.class);
  nm.createNotificationChannel(new NotificationChannel("parent_control","观看时间管理",NotificationManager.IMPORTANCE_LOW));
  Intent open=new Intent(this,MainActivity.class).setData(Uri.parse(NativeState.ORIGIN));
  PendingIntent pi=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
  Notification n=new Notification.Builder(this,"parent_control").setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
   .setContentTitle("电视时间管理正在运行").setContentText("家长已启用观看提醒与休息规则").setOngoing(true).setContentIntent(pi).build();
  if(Build.VERSION.SDK_INT>=34)startForeground(1,n,android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else startForeground(1,n);
  foregroundType=Build.VERSION.SDK_INT>=29?getForegroundServiceType():-1;NativeState.log(this,"FOREGROUND_TYPE "+foregroundType);
 }
 @Override public int onStartCommand(Intent intent,int flags,int id){
  if(!NativeState.enabled(this)){stopSelf();return START_NOT_STICKY;}
  if(worker==null||!worker.isAlive()){
   Recovery.schedule(this);stop=false;running=true;worker=new Thread(this::loop,"tv-native-monitor");worker.start();
   NativeState.log(this,"NATIVE_START uid="+android.os.Process.myUid()+" boot_count="+android.provider.Settings.Global.getInt(getContentResolver(),"boot_count",-1));
  }
  return START_STICKY;
 }
 @Override public IBinder onBind(Intent i){return null;}
 private void status(String value,String app){NativeState.prefs(this).edit().putString("last_status",value).putString("last_app",app).apply();}
 private void loop(){
  PowerManager power=getSystemService(PowerManager.class);
  while(!stop&&NativeState.enabled(this)){
   long began=SystemClock.elapsedRealtime();PowerManager.WakeLock wake=power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"tvtime:sample");
   try{
    wake.acquire(15000);tick(power.isInteractive());
   }catch(InterruptedException e){Thread.currentThread().interrupt();break;}
   catch(Exception e){releaseFocus();status("bypass_detection_error","");NativeState.log(this,"DETECTION_UNKNOWN Bypass check "+e.getClass().getSimpleName()+" "+(e instanceof IOException?e.getMessage():"operation_failed"));}
   finally{if(wake.isHeld())wake.release();}
   long delay=Math.max(1000,10000-(SystemClock.elapsedRealtime()-began));
   try{Thread.sleep(delay);}catch(InterruptedException e){Thread.currentThread().interrupt();break;}
  }
  releaseFocus();running=false;
 }
 private void tick(boolean interactive)throws Exception{
  if(checkSelfPermission("android.permission.DUMP")!=PackageManager.PERMISSION_GRANTED||ControlAccessibilityService.instance==null){
   releaseFocus();status("permission_missing","");NativeState.log(this,"PERMISSION_MISSING Bypass check");return;
  }
  String app=interactive?PlaybackProbe.foreground():"android";
  boolean watched=NativeState.APPS.contains(app),playing=false;int uid=-1;
  if(watched){uid=getPackageManager().getApplicationInfo(app,0).uid;playing=PlaybackProbe.playing(uid);}
  JSONObject response;
  try{
   JSONObject health=request("/healthz",null);if(!"ok".equals(health.optString("status")))throw new IOException("Invalid health");
   SharedPreferences p=NativeState.prefs(this);JSONObject body=new JSONObject();body.put("device",p.getString("device",""));body.put("app",app);
   body.put("is_playing",playing);body.put("event_id",UUID.randomUUID().toString());body.put("client_mode","native");
   body.put("adb_enabled",android.provider.Settings.Global.getInt(getContentResolver(),"adb_enabled",-1));
   body.put("boot_count",android.provider.Settings.Global.getInt(getContentResolver(),"boot_count",-1));
   response=request("/heartbeat",body);
   String result=response.optString("status");if(!result.equals("allow")&&!result.equals("lock"))throw new IOException("Invalid response");
   p.edit().putLong("last_heartbeat_ms",System.currentTimeMillis()).apply();
  }catch(Exception e){releaseFocus();status("cloud_down",app);NativeState.log(this,"CLOUD_DOWN Bypass check "+e.getClass().getSimpleName());return;}
  if(stop||!NativeState.enabled(this)){releaseFocus();return;}
  String result=response.getString("status");status(result,app);
  NativeState.log(this,"HEARTBEAT status="+result+" app="+app+" playing="+playing+" mode="+NativeState.prefs(this).getString("mode","observe"));
  if(result.equals("allow")){releaseFocus();return;}
  if(!"enforce".equals(NativeState.prefs(this).getString("mode","observe"))||!watched||!interactive)return;
  String url=response.optString("launch_url");
  if(!url.matches("https://tv\\.example\\.com/#ticket=[A-Za-z0-9_-]{43}"))throw new IOException("Invalid launch ticket");
  if(SystemClock.elapsedRealtime()-lastLaunch<8000||!app.equals(PlaybackProbe.foreground()))return;
  ControlAccessibilityService a=ControlAccessibilityService.instance;if(a==null)return;
  // 标准媒体暂停不需要INJECT_EVENTS。音频焦点+系统返回使无媒体会话的视频也退出播放器。
  AudioManager audio=getSystemService(AudioManager.class);
  audio.dispatchMediaKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN,android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
  audio.dispatchMediaKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_UP,android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
  audioFocus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
   .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
   .setOnAudioFocusChangeListener(change->{},new Handler(Looper.getMainLooper())).build();
  hasFocus=audio.requestAudioFocus(audioFocus)==AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
  for(int attempt=0;attempt<3;attempt++){
   if(!PlaybackProbe.playing(uid)||!app.equals(PlaybackProbe.foreground()))break;
   boolean sent=a.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK);
   NativeState.log(this,"BLOCK_BACK attempt="+(attempt+1)+" delivered="+sent);Thread.sleep(400);
  }
  a.startActivity(new Intent(a,MainActivity.class).setAction(Intent.ACTION_VIEW).setData(Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP));
  lastLaunch=SystemClock.elapsedRealtime();Thread.sleep(700);
  boolean visible=getPackageName().equals(PlaybackProbe.foreground()),silent=!PlaybackProbe.playing(uid);
  NativeState.log(this,"LOCK_RESULT visible="+visible+" video_audio_stopped="+silent);
 }
 private JSONObject request(String path,JSONObject body)throws Exception{
  HttpsURLConnection c=(HttpsURLConnection)new URL(NativeState.ORIGIN+path).openConnection(java.net.Proxy.NO_PROXY);
  c.setConnectTimeout(2000);c.setReadTimeout(2000);c.setInstanceFollowRedirects(false);c.setRequestProperty("Accept","application/json");
  try{
   if(body!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("Authorization","Bearer "+NativeState.prefs(this).getString("token",""));
    byte[] bytes=body.toString().getBytes(StandardCharsets.UTF_8);c.setFixedLengthStreamingMode(bytes.length);try(OutputStream out=c.getOutputStream()){out.write(bytes);}}
   if(c.getResponseCode()!=200)throw new IOException("Non-200");
   try(InputStream in=c.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream()){
    byte[] b=new byte[1024];int n;while((n=in.read(b))!=-1){if(bytes.size()+n>16384)throw new IOException("Too large");bytes.write(b,0,n);}return new JSONObject(bytes.toString("UTF-8"));
   }
  }finally{c.disconnect();}
 }
 private synchronized void releaseFocus(){if(hasFocus&&audioFocus!=null)getSystemService(AudioManager.class).abandonAudioFocusRequest(audioFocus);hasFocus=false;audioFocus=null;}
 @Override public void onDestroy(){stop=true;if(worker!=null)worker.interrupt();releaseFocus();running=false;NativeState.log(this,"NATIVE_STOP");super.onDestroy();}
}
