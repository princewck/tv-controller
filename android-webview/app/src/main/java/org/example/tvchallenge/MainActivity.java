package org.example.tvchallenge;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.net.http.SslError;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.*;
import android.widget.TextView;
import java.io.ByteArrayInputStream;

/** 最小的电视HTTPS容器。仅限指定域名，不提供系统级Kiosk/反卸载能力。 */
public class MainActivity extends Activity {
    private WebView web;
    private static final String ORIGIN="https://tv.example.com";
    private boolean trusted(Uri uri) {
        return uri!=null && "https".equals(uri.getScheme()) && "tv.example.com".equals(uri.getHost())
            && uri.getUserInfo()==null && (uri.getPort()==-1 || uri.getPort()==443);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if(NativeState.enabled(this))MonitorService.start(this);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        if(WebView.getCurrentWebViewPackage()==null){
            TextView text=new TextView(this);text.setText("系统没有可用WebView，请由家长处理。返回键可退出。");text.setTextSize(30);setContentView(text);return;
        }
        WebView.setWebContentsDebuggingEnabled(false);
        web=new WebView(this);setContentView(web);
        WebSettings settings=web.getSettings();
        settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(false);
        settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);settings.setSupportMultipleWindows(false);
        settings.setSafeBrowsingEnabled(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);
        // 不提供addJavascriptInterface，网页不能读取令牌或直接调用shell。
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){return !trusted(request.getUrl());}
            @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){
                if(!trusted(request.getUrl()))return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));
                return null;
            }
            @Override public void onReceivedSslError(WebView view,SslErrorHandler handler,SslError error){handler.cancel();}
        });
        open(getIntent());
    }
    private void open(Intent intent){
        if(web==null)return;
        Uri uri=intent==null?null:intent.getData();
        web.loadUrl(uri==null?ORIGIN:trusted(uri)?uri.toString():ORIGIN);
        web.requestFocus();
    }
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);open(intent);}
    @Override public void onBackPressed(){
        if(web==null){finish();return;}
        // 对实际网页状态进行异步查询。断网时前端会放行；页面尚未初始化也允许退出。
        android.os.Handler handler=new android.os.Handler(android.os.Looper.getMainLooper());
        Runnable escape=this::finish;handler.postDelayed(escape,1500);
        web.evaluateJavascript("typeof locked==='boolean' && locked",value->{handler.removeCallbacks(escape);if(!"true".equals(value))finish();});
    }
    @Override public boolean onKeyDown(int code,KeyEvent event){
        // 菜单键交由网页处理；Home、电源和系统UI始终由Android控制。
        if(code==KeyEvent.KEYCODE_MENU && web!=null){web.dispatchKeyEvent(event);return true;}
        return super.onKeyDown(code,event);
    }
    @Override protected void onDestroy(){if(web!=null){web.stopLoading();web.destroy();web=null;}super.onDestroy();}
}
