package org.example.tvchallenge;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONObject;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.*;

/** 凭证只保存在应用私有目录；诊断绝不输出令牌、票据或答题内容。 */
final class NativeState {
 static final String DEFAULT_ORIGIN="https://familytv-api.princewck.workers.dev";
 static String origin(Context c){return prefs(c).getString("origin",DEFAULT_ORIGIN);}
 static boolean trustedOrigin(String value){return DEFAULT_ORIGIN.equals(value)||"https://tv.chengkai.wang".equals(value);}
 static final Set<String> APPS=Collections.unmodifiableSet(new HashSet<>(Arrays.asList("com.ktcp.video","com.xiaodianshi.tv.yst","com.newtv.cboxtv","com.google.android.youtube.tv","com.fongmi.android.tv","com.gitvdemo.video","com.hunantv.license")));
 static SharedPreferences prefs(Context c){return c.getSharedPreferences("native_control",Context.MODE_PRIVATE);}
 static boolean enabled(Context c){return prefs(c).getBoolean("enabled",false);}
 static synchronized void provision(Context c,JSONObject body)throws Exception{
  SharedPreferences p=prefs(c);String token=body.optString("token",p.getString("token","")),device=body.optString("device",p.getString("device",""));
  String origin=body.optString("origin",origin(c));if(!trustedOrigin(origin))throw new IllegalArgumentException("Unsupported service origin");
  boolean enabled=body.optBoolean("enabled",p.getBoolean("enabled",false));String mode=body.optString("mode",p.getString("mode","observe"));
  if(enabled&&(!token.matches("[A-Za-z0-9_-]{32,128}")||!device.matches("[A-Za-z0-9_-]{1,64}")))throw new IllegalArgumentException("Invalid credentials");
  if(!mode.equals("observe")&&!mode.equals("enforce"))throw new IllegalArgumentException("Invalid mode");
  if(!device.equals(p.getString("device",""))||!origin.equals(origin(c))){if(!p.edit().clear().commit())throw new IOException("Reset failed");}
  if(!p.edit().putString("origin",origin).putString("token",token).putString("device",device).putString("mode",mode).putBoolean("enabled",enabled).commit())throw new IOException("Commit failed");
  log(c,"CONFIG_UPDATED enabled="+enabled+" mode="+mode);
 }
 static synchronized void log(Context c,String message){
  try{File f=new File(c.getFilesDir(),"native-events.log");if(f.length()>1048576){File old=new File(c.getFilesDir(),"native-events.log.1");if(old.exists()&&!old.delete())return;if(!f.renameTo(old))return;}
   SimpleDateFormat df=new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",Locale.ROOT);df.setTimeZone(TimeZone.getTimeZone("UTC"));
   try(FileOutputStream out=new FileOutputStream(f,true)){out.write((df.format(new Date())+" "+message+"\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));}
  }catch(IOException ignored){}
 }
}
