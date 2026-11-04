package org.example.tvchallenge;

import android.content.*;
import android.content.SharedPreferences;
import android.provider.Settings;
import android.app.job.JobScheduler;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.*;
import org.junit.runner.RunWith;
import org.json.*;
import java.text.SimpleDateFormat;
import java.util.*;
import static org.junit.Assert.*;

/** Runs in the disposable emulator's real Android storage/runtime, with networking disabled. */
@RunWith(AndroidJUnit4.class)
public class OfflineRuntimeTest {
 private Context c;private SharedPreferences p;private OfflineState cache;
 private static final String APP="com.ktcp.video";
 private static final long BASE=1893902400000L;
 @Before public void before(){c=InstrumentationRegistry.getInstrumentation().getTargetContext();c.stopService(new Intent(c,MonitorService.class));p=NativeState.prefs(c);p.edit().clear().commit();cache=new OfflineState(c);}
 @After public void after(){p.edit().putBoolean("enabled",false).commit();Recovery.cancel(c);c.stopService(new Intent(c,MonitorService.class));p.edit().clear().commit();}
 private String day(long now){SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd",Locale.ROOT);f.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));return f.format(new Date(now));}
 private JSONObject state(long now,int watched,int limit,boolean paused,int bonus)throws Exception{
  JSONObject policy=new JSONObject().put("daily_limit_seconds",limit).put("banned_windows",new JSONArray());
  return new JSONObject().put("day",day(now)).put("watched_seconds",watched).put("paused",paused).put("override_seconds",bonus).put("bonus_expires_ms",now+86400000).put("server_now_ms",now).put("control_revision",1).put("policy_snapshot",policy).put("accepted_usage_ids",new JSONArray());
 }
 private void time(long now){p.edit().putLong("server_offset",now-System.currentTimeMillis()).commit();}
 @Test public void missingRulesDoNotInventACache()throws Exception{
  try{cache.state();fail("No rules must remain unconfigured");}catch(IllegalStateException expected){}
 }
 @Test public void quotaAndRetryAcknowledgementSurviveRecreation()throws Exception{
  cache.accept(state(BASE,40,60,false,0));assertEquals("allow",cache.state().getString("status"));
  cache.record(APP,10);cache.record(APP,10);JSONArray pending=cache.samples();assertEquals(2,pending.length());String first=pending.getJSONObject(0).getString("id"),second=pending.getJSONObject(1).getString("id");
  cache=new OfflineState(c);assertEquals("lock",cache.state().getString("status"));
  JSONObject firstAck=state(BASE+10000,50,60,false,0).put("accepted_usage_ids",new JSONArray().put(first));cache.accept(firstAck);
  assertEquals(1,cache.samples().length());assertEquals(second,cache.samples().getJSONObject(0).getString("id"));assertEquals(60,p.getInt("local_used",-1));
  cache.accept(state(BASE+20000,60,60,false,0).put("accepted_usage_ids",new JSONArray().put(second)));assertEquals(0,cache.samples().length());assertEquals("lock",new OfflineState(c).state().getString("status"));
 }
 @Test public void midnightResetsDailyBudgetButRetainsParentPause()throws Exception{
  cache.accept(state(BASE,60,60,false,0));assertEquals("lock",cache.state().getString("status"));time(BASE+86400000);assertEquals("allow",cache.state().getString("status"));
  cache.record(APP,10);assertEquals(10,p.getInt("local_used",-1));
  cache.accept(state(BASE+86400000,10,60,true,30));time(BASE+2L*86400000);assertEquals("lock",new OfflineState(c).state().getString("status"));assertEquals("parent_paused",cache.state().getString("lock_reason"));
 }
 @Test public void overnightQuietWindowUsesThePreviousDay()throws Exception{
  SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd HH:mm",Locale.ROOT);f.setTimeZone(TimeZone.getTimeZone("Asia/Shanghai"));long sunday=f.parse("2030-01-06 23:00").getTime();
  JSONObject s=state(sunday,0,5400,false,0);s.getJSONObject("policy_snapshot").getJSONArray("banned_windows").put(new JSONObject().put("enabled",true).put("days",new JSONArray().put(0)).put("start","22:00").put("end","07:00"));
  cache.accept(s);assertEquals("restricted_time",cache.state().getString("lock_reason"));time(f.parse("2030-01-07 06:00").getTime());assertEquals("lock",cache.state().getString("status"));
  time(f.parse("2030-01-07 07:30").getTime());JSONObject allowed=cache.state();assertEquals("allow",allowed.getString("status"));assertTrue("Allowed state must not expose a lock reason",allowed.isNull("lock_reason"));
 }
 @Test public void bonusCannotBypassPauseAndExpiresOffline()throws Exception{
  cache.accept(state(BASE,100,60,true,30));assertEquals("lock",cache.state().getString("status"));
  cache.accept(state(BASE,100,60,false,30).put("bonus_expires_ms",BASE+300000));assertEquals("allow",cache.state().getString("status"));cache.record(APP,10);assertEquals(20,p.getInt("local_bonus",-1));
  time(BASE+1200000);assertEquals("lock",cache.state().getString("status"));
  time(BASE+86400001L);assertEquals("allow",cache.state().getString("status"));
  cache.record(APP,10);cache.record(APP,10);cache.record(APP,10);cache.record(APP,10);cache.record(APP,10);cache.record(APP,10);assertEquals("lock",cache.state().getString("status"));
 }
 @Test public void changingTheBoundDeviceClearsPriorRulesAndJournal()throws Exception{
  String token=UUID.randomUUID().toString().replace("-","")+"01234567890";
  NativeState.provision(c,new JSONObject().put("origin",NativeState.DEFAULT_ORIGIN).put("device","tv_a").put("token",token).put("enabled",true).put("mode","observe"));
  cache.accept(state(BASE,10,60,false,0));cache.record(APP,10);
  NativeState.provision(c,new JSONObject().put("origin",NativeState.DEFAULT_ORIGIN).put("device","tv_b").put("token",token).put("enabled",true).put("mode","enforce"));
  assertFalse(p.contains("cached_state"));assertFalse(p.contains("usage_queue"));assertEquals("tv_b",p.getString("device",""));
  try{NativeState.provision(c,new JSONObject().put("origin","https://untrusted.invalid"));fail("Untrusted origin accepted");}catch(IllegalArgumentException expected){}
  assertEquals("tv_b",p.getString("device",""));
 }
 @Test public void parentDisabledAccessibilityMustStayDisabled()throws Exception{
  String old=Settings.Secure.getString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);int enabled=Settings.Secure.getInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,0);
  try{
   Settings.Secure.putString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,"");Settings.Secure.putInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,0);Thread.sleep(500);
   assertEquals("Confirm disabled baseline before recovery",0,Settings.Secure.getInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,0));p.edit().putBoolean("enabled",true).commit();
   Recovery.check(c);Thread.sleep(1000);assertEquals(0,Settings.Secure.getInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,0));assertEquals("",Settings.Secure.getString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES));
  }finally{p.edit().putBoolean("enabled",false).commit();Settings.Secure.putString(c.getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,old);Settings.Secure.putInt(c.getContentResolver(),Settings.Secure.ACCESSIBILITY_ENABLED,enabled);}
 }
}
