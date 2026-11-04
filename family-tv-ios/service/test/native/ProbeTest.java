package org.example.tvchallenge;
import java.io.IOException;
import java.nio.file.*;
public class ProbeTest {
 public static void main(String[] args)throws Exception{
  String active="players:\n AudioPlaybackConfiguration type:android.media.AudioTrack u/pid:10074/123 state:started attr: usage=USAGE_MEDIA\nEvents log:\n";
  if(!PlaybackProbe.playing(active,10074)||PlaybackProbe.playing(active,10075))throw new AssertionError("owner");
  if(PlaybackProbe.playing(active.replace("state:started","state:paused"),10074))throw new AssertionError("paused");
  if(PlaybackProbe.playing(active.replace("type:android.media.AudioTrack","type:android.media.SoundPool"),10074))throw new AssertionError("soundpool");
  if(PlaybackProbe.playing("players:\nEvents log:\n"+active.replace("players:\n", ""),10074))throw new AssertionError("historical events");
  if(PlaybackProbe.playing(active.replace("10074/123","1000/123"),1000))throw new AssertionError("shared uid");
  boolean unknown=false;try{PlaybackProbe.playing("Permission Denial",10074);}catch(IOException e){unknown=true;}if(!unknown)throw new AssertionError("unknown format");
  PlaybackProbe.playing(Files.readString(Path.of(args[0])),10074);
  System.out.println("Native audio parser: ownership, paused, soundpool, history, shared uid, permission denial and real dump passed");
 }
}
