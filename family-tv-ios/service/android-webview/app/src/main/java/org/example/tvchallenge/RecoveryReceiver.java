package org.example.tvchallenge;
import android.content.*;
public class RecoveryReceiver extends BroadcastReceiver {
 @Override public void onReceive(Context context,Intent intent){Recovery.check(context);}
}
