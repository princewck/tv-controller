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
 private long lastLaunch,lastSample;
 private OfflineState offline;
 static void start(Context c){
  try{c.startForegroundService(new Intent(c,MonitorService.class));}
  catch(RuntimeException e){NativeState.log(c,"SERVICE_START_FAILED "+e.getClass().getSimpleName());}
 }
 @Override public void onCreate(){
  super.onCreate();offline=new OfflineState(this);NotificationManager nm=getSystemService(NotificationManager.class);
  nm.createNotificationChannel(new NotificationChannel("parent_control","观看时间管理",NotificationManager.IMPORTANCE_LOW));
  Intent open=new Intent(this,MainActivity.class).setData(Uri.parse(NativeState.origin(this)));
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
  SharedPreferences p=NativeState.prefs(this);
  boolean permissions=checkSelfPermission("android.permission.DUMP")==PackageManager.PERMISSION_GRANTED&&ControlAccessibilityService.instance!=null;
  String app=permissions&&interactive?PlaybackProbe.foreground():"android";
  boolean watched=NativeState.APPS.contains(app),playing=false;int uid=-1;
  if(watched){uid=getPackageManager().getApplicationInfo(app,0).uid;playing=PlaybackProbe.playing(uid);}
  long sampled=SystemClock.elapsedRealtime();int seconds=lastSample==0?0:(int)Math.max(0,Math.min(10,(sampled-lastSample)/1000));lastSample=sampled;
  if(playing)offline.record(app,seconds);
  JSONObject response;
  try{
   JSONObject body=new JSONObject();body.put("device",p.getString("device",""));body.put("app",watched?app:"android");
   body.put("is_playing",playing);body.put("event_id",UUID.randomUUID().toString());body.put("client_mode","native");
   body.put("usage_samples",offline.samples());body.put("permissions_ok",permissions);
   body.put("adb_enabled",android.provider.Settings.Global.getInt(getContentResolver(),"adb_enabled",-1));
   body.put("boot_count",android.provider.Settings.Global.getInt(getContentResolver(),"boot_count",-1));
   long revision=p.getLong("applied_revision",0);body.put("applied_revision",revision);body.put("enforcement_result",p.getString("enforcement_result","observing"));body.put("playback_stop_verified",p.getBoolean("playback_stop_verified",false));
   response=request("/heartbeat",body);
   if(!"daily".equals(response.optString("mode")))throw new IOException("Unsupported service protocol");
   String result=response.optString("status");if(!result.equals("allow")&&!result.equals("lock"))throw new IOException("Invalid response");
   offline.accept(response);response=offline.state();p.edit().putLong("last_heartbeat_ms",offline.now()).apply();
  }catch(DeviceRevoked e){
   p.edit().clear().putBoolean("enabled",false).putString("last_status","unpaired").commit();
   Recovery.cancel(this);releaseFocus();stopSelf();return;
  }catch(Exception e){
   status("cloud_down",app);NativeState.log(this,"CLOUD_DOWN cached_policy "+e.getClass().getSimpleName());
   try{response=offline.state();}catch(Exception absent){releaseFocus();status("waiting_for_configuration",app);return;}
  }
  if(!permissions){releaseFocus();p.edit().putString("enforcement_result","failed").putBoolean("playback_stop_verified",false).apply();status("permission_missing",app);return;}
  if(stop||!NativeState.enabled(this)){releaseFocus();return;}
  String result=response.getString("status");status(result,app);
  NativeState.log(this,"HEARTBEAT status="+result+" app="+app+" playing="+playing+" mode="+NativeState.prefs(this).getString("mode","observe"));
  long revision=response.optLong("control_revision",0);
  boolean enforcing="enforce".equals(p.getString("mode","observe"));
  if(!enforcing){releaseFocus();p.edit().putLong("applied_revision",revision).putString("enforcement_result","observing").putBoolean("playback_stop_verified",false).apply();return;}
  if(result.equals("allow")){releaseFocus();p.edit().putLong("applied_revision",revision).putString("enforcement_result","allowed").putBoolean("playback_stop_verified",false).apply();return;}
  if(!"enforce".equals(NativeState.prefs(this).getString("mode","observe"))||!watched||!interactive)return;
  if(SystemClock.elapsedRealtime()-lastLaunch<8000||!app.equals(PlaybackProbe.foreground()))return;
  ControlAccessibilityService a=ControlAccessibilityService.instance;if(a==null)return;
  // 标准媒体暂停不需要INJECT_EVENTS。音频焦点+系统返回使无媒体会话的视频也退出播放器。
  pauseMedia();
  for(int attempt=0;attempt<3;attempt++){
   if(!PlaybackProbe.playing(uid)||!app.equals(PlaybackProbe.foreground()))break;
   boolean sent=a.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK);
   NativeState.log(this,"BLOCK_BACK attempt="+(attempt+1)+" delivered="+sent);Thread.sleep(400);
  }
  a.startActivity(new Intent(a,MainActivity.class).setAction(Intent.ACTION_VIEW).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP));
  lastLaunch=SystemClock.elapsedRealtime();Thread.sleep(700);
  boolean visible=getPackageName().equals(PlaybackProbe.foreground()),silent=!PlaybackProbe.playing(uid);
  p.edit().putLong("applied_revision",revision).putString("enforcement_result",visible&&silent?"stopped":"failed").putBoolean("playback_stop_verified",visible&&silent).apply();
  NativeState.log(this,"LOCK_RESULT visible="+visible+" video_audio_stopped="+silent);
 }
 private void pauseMedia(){
  releaseFocus();
  AudioManager audio=getSystemService(AudioManager.class);
  audio.dispatchMediaKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN,android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
  audio.dispatchMediaKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_UP,android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
  audioFocus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
   .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
   .setOnAudioFocusChangeListener(change->{},new Handler(Looper.getMainLooper())).build();
  hasFocus=audio.requestAudioFocus(audioFocus)==AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
 }
 private static final class DeviceRevoked extends IOException {}
 private JSONObject request(String path,JSONObject body)throws Exception{
  HttpsURLConnection c=(HttpsURLConnection)new URL(NativeState.origin(this)+path).openConnection(java.net.Proxy.NO_PROXY);
  c.setConnectTimeout(2000);c.setReadTimeout(2000);c.setInstanceFollowRedirects(false);c.setRequestProperty("Accept","application/json");
  try{
   if(body!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("Authorization","Bearer "+NativeState.prefs(this).getString("token",""));
    byte[] bytes=body.toString().getBytes(StandardCharsets.UTF_8);c.setFixedLengthStreamingMode(bytes.length);try(OutputStream out=c.getOutputStream()){out.write(bytes);}}
   if(c.getResponseCode()==401)throw new DeviceRevoked();
   if(c.getResponseCode()!=200)throw new IOException("Non-200");
   try(InputStream in=c.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream()){
    byte[] b=new byte[1024];int n;while((n=in.read(b))!=-1){if(bytes.size()+n>16384)throw new IOException("Too large");bytes.write(b,0,n);}return new JSONObject(bytes.toString("UTF-8"));
   }
  }finally{c.disconnect();}
 }
 private synchronized void releaseFocus(){if(hasFocus&&audioFocus!=null)getSystemService(AudioManager.class).abandonAudioFocusRequest(audioFocus);hasFocus=false;audioFocus=null;}
 @Override public void onDestroy(){stop=true;if(worker!=null)worker.interrupt();releaseFocus();running=false;NativeState.log(this,"NATIVE_STOP");super.onDestroy();}
}
