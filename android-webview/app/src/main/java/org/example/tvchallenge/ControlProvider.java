package org.example.tvchallenge;

import android.content.*;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import org.json.JSONObject;
import java.io.*;

/** 仅持有系统DUMP权限的运维端可配置。content write从stdin取密钥，不放到命令行/URL。 */
public class ControlProvider extends ContentProvider {
 @Override public boolean onCreate(){return true;}
 @Override public String getType(Uri uri){return "application/json";}
 @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String order){
  if(!"/status".equals(uri.getPath()))throw new IllegalArgumentException("Unknown URI");
  JSONObject state=new JSONObject();try{
   android.content.Context c=getContext();android.content.SharedPreferences p=NativeState.prefs(c);
   state.put("enabled",NativeState.enabled(c));state.put("mode",p.getString("mode","observe"));state.put("device",p.getString("device",""));
   state.put("native_service_running",MonitorService.running);state.put("foreground_service_type",MonitorService.foregroundType);state.put("accessibility_bound",ControlAccessibilityService.instance!=null);
   state.put("dump_granted",c.checkSelfPermission("android.permission.DUMP")==PackageManager.PERMISSION_GRANTED);
   state.put("overlay_granted",android.provider.Settings.canDrawOverlays(c));state.put("last_heartbeat_ms",p.getLong("last_heartbeat_ms",0));
   state.put("last_status",p.getString("last_status","not_started"));state.put("last_app",p.getString("last_app",""));
   state.put("battery_exempt",c.getSystemService(android.os.PowerManager.class).isIgnoringBatteryOptimizations(c.getPackageName()));
  }catch(Exception ignored){}
  MatrixCursor cursor=new MatrixCursor(new String[]{"status_json"});cursor.addRow(new Object[]{state.toString()});return cursor;
 }
 @Override public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{
  if("/events".equals(uri.getPath())&&"r".equals(mode))return ParcelFileDescriptor.open(new File(getContext().getFilesDir(),"native-events.log"),ParcelFileDescriptor.MODE_READ_ONLY);
  if(!"/config".equals(uri.getPath())||!"w".equals(mode))throw new FileNotFoundException("Unknown operation");
  try{
   ParcelFileDescriptor[] pipe=ParcelFileDescriptor.createReliablePipe();
   new Thread(()->{try(InputStream in=new ParcelFileDescriptor.AutoCloseInputStream(pipe[0])){
    ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] b=new byte[1024];int n;while((n=in.read(b))!=-1){if(bytes.size()+n>8192)throw new IOException("Too large");bytes.write(b,0,n);}
    NativeState.provision(getContext(),new JSONObject(bytes.toString("UTF-8")));
    if(NativeState.enabled(getContext())){Recovery.schedule(getContext());Recovery.check(getContext());}else{Recovery.cancel(getContext());getContext().stopService(new Intent(getContext(),MonitorService.class));}
   }catch(Exception e){NativeState.log(getContext(),"CONFIG_FAILED "+e.getClass().getSimpleName());}finally{try{pipe[0].close();}catch(IOException ignored){}}},"tv-provision").start();return pipe[1];
  }catch(IOException e){throw new FileNotFoundException("Pipe unavailable");}
 }
 @Override public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}
 @Override public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
 @Override public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}
}
