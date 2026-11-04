package org.example.tvchallenge;
import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;
/** 仅用于受限视频的系统返回操作和后台弹页授权；不读取文字、不过滤遥控器按键。 */
public class ControlAccessibilityService extends AccessibilityService {
 static volatile ControlAccessibilityService instance;
 @Override protected void onServiceConnected(){instance=this;NativeState.log(this,"ACCESSIBILITY_BOUND");if(NativeState.enabled(this))MonitorService.start(this);}
 @Override public void onAccessibilityEvent(AccessibilityEvent event){}
 @Override public void onInterrupt(){}
 @Override public void onDestroy(){instance=null;NativeState.log(this,"ACCESSIBILITY_UNBOUND");super.onDestroy();}
}
