package org.example.tvchallenge;
import android.app.Activity;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

/** The break screen is native and remains available without Internet access. */
public class MainActivity extends Activity {
 @Override public void onCreate(Bundle state){
  super.onCreate(state);if(NativeState.enabled(this))MonitorService.start(this);
  TextView text=new TextView(this);text.setGravity(Gravity.CENTER);text.setTextSize(30);text.setPadding(64,48,64,48);text.setTextColor(0xfff5faf6);text.setBackgroundColor(0xff123f34);
  text.setText("电视休息一下\n\n请家长在手机上调整观看时间。\n恢复后，按返回键继续观看。\n\n系统设置与家长维护入口始终可用。");setContentView(text);
 }
}
