package org.example.tvchallenge;
import android.app.job.*;
public class RecoveryJob extends JobService {
 @Override public boolean onStartJob(JobParameters params){Recovery.check(this);return false;}
 @Override public boolean onStopJob(JobParameters params){return true;}
}
