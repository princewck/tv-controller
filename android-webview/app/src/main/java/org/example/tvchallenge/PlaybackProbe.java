package org.example.tvchallenge;

import java.io.*;
import java.util.concurrent.*;
import java.util.regex.*;

/** 只读取当前音轨，不扫描历史started日志；普通应用UID执行，DUMP由家长一次授权。 */
final class PlaybackProbe {
 private static final Pattern FOCUS=Pattern.compile("mCurrentFocus=.*?\\s([A-Za-z0-9_.]+)/([A-Za-z0-9_.$]+)");
 private static final Pattern OWNER=Pattern.compile("(?:u/pid|uid/pid):([0-9]+)/([0-9]+)");
 static String command(String... args)throws Exception{
  // timeout同样在电视应用UID运行，不通过shell拼接字符串或调用ADB。
  String[] command=new String[args.length+2];command[0]="/system/bin/timeout";command[1]="2";System.arraycopy(args,0,command,2,args.length);
  Process p=new ProcessBuilder(command).redirectErrorStream(true).start();
  try(InputStream in=p.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream()){
   byte[] buffer=new byte[8192];int n;while((n=in.read(buffer))!=-1){if(bytes.size()+n>2*1024*1024)throw new IOException("Dump too large");bytes.write(buffer,0,n);}
   if(!p.waitFor(2500,TimeUnit.MILLISECONDS)||p.exitValue()!=0)throw new IOException("Dump command did not finish successfully");return bytes.toString("UTF-8");
  }finally{p.destroy();}
 }
 static String foreground()throws Exception{
  Matcher m=FOCUS.matcher(command("dumpsys","window"));if(!m.find())throw new IOException("Focus unavailable");return m.group(1);
 }
 static String foregroundComponent()throws Exception{
  Matcher m=FOCUS.matcher(command("dumpsys","window"));if(!m.find())throw new IOException("Focus unavailable");return m.group(1)+"/"+m.group(2);
 }
 static boolean playing(String dump,int uid)throws IOException{
  boolean section=false,recognized=false;for(String line:dump.split("\n")){
   if(line.trim().equals("players:")){section=true;recognized=true;continue;}
   if(section&&line.trim().matches("^(ducked players|faded out players|muted player|banned uids|Events log).*"))section=false;
   if(!section||!line.contains("AudioPlaybackConfiguration")||!line.matches(".*state:started(?:\\s|$).*"))continue;
   Matcher owner=OWNER.matcher(line);if(owner.find()&&Integer.parseInt(owner.group(1))==uid&&uid>=10000&&!line.contains("type:android.media.SoundPool")&&(line.contains("usage=USAGE_MEDIA")||line.contains("usage=USAGE_UNKNOWN")))return true;
  }
  if(!recognized)throw new IOException("Unknown audio format");return false;
 }
 static boolean playing(int uid)throws Exception{return playing(command("dumpsys","audio"),uid);}
}
