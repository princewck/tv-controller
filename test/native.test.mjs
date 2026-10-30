import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync,mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const javaHome=process.env.JAVA_HOME||'/Applications/Android Studio.app/Contents/jbr/Contents/Home';
test('原生音轨解析：归属、暂停、提示音、历史事件、共享UID及权限失败',{skip:!existsSync(join(javaHome,'bin/javac'))},()=>{
 const dir=mkdtempSync(join(tmpdir(),'tv-native-test-'));try{
  const source=new URL('../android-webview/app/src/main/java/org/example/tvchallenge/PlaybackProbe.java',import.meta.url).pathname;
  const tests=new URL('./native/ProbeTest.java',import.meta.url).pathname;
  const fixture=join(dir,'audio.txt');writeFileSync(fixture,'players:\n AudioPlaybackConfiguration type:android.media.AudioTrack u/pid:10074/123 state:paused attr: usage=USAGE_MEDIA\nEvents log:\n');
  const built=spawnSync(join(javaHome,'bin/javac'),['-d',dir,source,tests],{encoding:'utf8'});assert.equal(built.status,0,built.stderr);
  const run=spawnSync(join(javaHome,'bin/java'),['-cp',dir,'org.example.tvchallenge.ProbeTest',fixture],{encoding:'utf8'});assert.equal(run.status,0,run.stderr);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
